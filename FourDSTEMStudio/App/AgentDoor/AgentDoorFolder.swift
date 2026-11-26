//
//  AgentDoorFolder.swift
//  Role: The agent door's folder tools (issue #191): an agent works through the files of the one Agent folder the person chose in
//        Settings > Agents (`AgentFolder`): it lists them, opens one in a window as File > Open does, and saves the displayed
//        result there as File > Export > Result Image does. Batch work is a loop of these with the run tools
//        (`AgentDoorRuns.swift`).
//
//  Listing only looks. Opening acts, so it needs "Let agents run analyses"; saving also needs "Let agents save results there"
//  (`AppPreferences.agentFolderSavesEnabled`), off by default. A save never replaces a file: a name that exists is refused.
//  Nothing outside the folder is listed, opened or written.
//

import CoreGraphics
import ImageIO
import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// The Agent folder the tools work in.
    static let folder = AgentFolder()

    /// Whether the person lets agents write into the Agent folder (Settings > Agents).
    static var savesAllowed = false

    /// What a file tool answers when its path names no file; an empty path is the folder itself, never "no file <folder name>".
    static func noFileMessage(_ url: URL) -> String {
        guard let root = folder.url, url.standardizedFileURL.path != root.standardizedFileURL.path else {
            return "Give a path: a file of the Agent folder, as list_agent_folder shows it."
        }
        return "There is no file \(folder.relativePath(of: url)) in the Agent folder."
    }

    static let folderTools: [AgentTool] = [
        AgentTool(name: "list_agent_folder", title: "Agent folder files",
                  summary: "The files in the Agent folder the person chose in Settings > Agents (and its subfolders): path relative to "
                      + "the folder, size in bytes, modification date, sorted by path, and the folder's absolute path. path keeps one "
                      + "subfolder, pattern a shell glob (*.h5; with a / it matches the whole path), offset and limit page through "
                      + "the list: total counts every match. open_file opens one; the save tools save into the folder.",
                  input: .noWindow,
                  parameters: [
                      AgentParameter("path", .text, summary: "A subfolder, relative to the Agent folder; leave out for all of it."),
                      AgentParameter("pattern", .text, summary: "A shell glob, as *.dm4 or maps/*_strain.*."),
                      AgentParameter("offset", .integer(0...10_000_000), summary: "Files to skip in the sorted list (default 0)."),
                      AgentParameter("limit", .integer(1...10_000), summary: "Most files in this page (default 2000)."),
                  ]) { call in
            let offset = call.arguments["offset"].flatMap(Int.init) ?? 0
            let limit = call.arguments["limit"].flatMap(Int.init) ?? 2000
            guard let listed = folder.listing(under: call.arguments["path"], pattern: call.arguments["pattern"],
                                              offset: offset, limit: limit) else {
                return .refusal(status: 404, message: folder.missingMessage)
            }
            switch listed {
            case .failure(let refusal): return .refusal(status: 404, message: refusal.message)
            case .success(let page):
                return .json(["folder": folder.url?.lastPathComponent ?? "", "absolute_path": folder.url?.path ?? "",
                              "files": page.files, "total": page.total, "offset": offset,
                              "more": offset + page.files.count < page.total, "truncated": page.truncated])
            }
        },
        AgentTool(name: "open_file", title: "Open file",
                  summary: "Opens a file of the Agent folder in the window, as File > Open does, replacing the dataset it shows. As "
                      + "there, one window holds one kind: a spectrum image opened in a window with a 4D scan, or a 4D file in a "
                      + "window with only a spectrum image, opens in a NEW window: list_windows then names it. It "
                      + "starts the open and answers at once; get_window says busy until the dataset is in, and get_log says if it failed. "
                      + "Refused while an analysis runs, since opening would stop it. The answer's run_id reaches get_window's "
                      + "operation.finished_run_id when the open ends. without_session true opens the file with its saved session "
                      + "left aside, as Reopen Without Session does: the session file is neither read nor changed.",
                  input: .window,
                  parameters: [AgentParameter("path", .text, summary: "The file, relative to the Agent folder, as list_agent_folder "
                                                  + "names it.", required: true),
                               AgentParameter("without_session", .boolean, summary: "Leave the saved session aside for this open "
                                                  + "(default false): a fresh start on the same file.")],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            if let refusal = openRefusal(state) { return refusal }
            let file: URL
            switch folder.resolve(call.arguments["path"] ?? "") {
            case .success(let url): file = url
            case .failure(let refusal): return .refusal(status: 404, message: refusal.message)
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
                return .refusal(status: 404, message: noFileMessage(file))
            }
            // Busy from this answer on, not from the moment the open's own loading stage begins (#266: about a second later): the
            // window's open is claimed now (`claimOpen`, the one-load guard of #303, which every open shares).
            guard state.claimOpen() else { return busyRefusal }
            state.statusText = "An agent opened \(quotedAgentText(file.lastPathComponent))."
            let fresh = call.arguments["without_session"] == "true"
            if fresh { state.ignoreSessionForDatasetID = file.standardizedFileURL.path }
            let id = state.agentRun("open_file") { await state.openFileAsync(url: file, claimed: true) }
            return .json(["opening": folder.relativePath(of: file), "without_session": fresh, "run_id": id])
        },
        AgentTool(name: "save_result_image", title: "Save result picture",
                  summary: "Saves the displayed result into the Agent folder as File > Export > Result Image does: a PNG with the "
                      + "colour scale, scale bar and caption drawn in and the full provenance record in its metadata. Never replaces "
                      + "a file: a name that exists is refused.",
                  input: .window,
                  parameters: [AgentParameter("name", .text, summary: "The file name, sub-folders with /; .png is added. Leave out for "
                                                  + "the dataset's name followed by _result.")],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard savesAllowed else {
                return .refusal(status: 403, message: "Saving is off. Ask the person to turn on \"Let agents save results there\" in "
                    + "\(AppName.display)'s Settings > Agents.")
            }
            guard !state.agentBusy else { return busyRefusal }
            guard let root = folder.url else { return .refusal(status: 404, message: folder.missingMessage) }
            let name: String
            switch fileName(call.arguments["name"], default: state.exportBaseName + "_result") {
            case .success(let made): name = made
            case .failure(let refusal): return .refusal(status: 400, message: refusal.message)
            }
            let target: URL
            switch newFileTarget(name, in: root) {
            case .success(let made): target = made
            case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
            }
            let scale = state.preferences.exportScale.pixelScale
            let made: (image: CGImage, product: DisplayedProduct)
            do { made = try state.resultExportImage(scale: scale) } catch {
                return .refusal(status: 404, message: error.localizedDescription)
            }
            let properties = AppState.pngProperties(title: state.currentResultDisplayName,
                                                    record: state.exportedImageProvenanceRecord(), pixelScale: scale)
            // Encoded in memory, then written only as a new file (O_EXCL): a file or link that appeared after the check above is
            // never replaced or followed.
            guard let png = pngData(made.image, properties: properties) else {
                return .refusal(status: 500, message: "Encoding \(name) failed.")
            }
            do { try png.write(to: target, options: .withoutOverwriting) } catch {
                return .refusal(status: 409, message: "\(name) could not be written as a new file in the Agent folder: "
                    + error.localizedDescription)
            }
            state.statusText = "An agent saved \(name) in the Agent folder."
            state.recordExportRun(format: "png", fileName: name, productKind: made.product.kind,
                                  productStep: made.product.provenance["lineage_step"])
            return .json(["saved": name, "width": made.image.width, "height": made.image.height])
        },
    ]

    /// The PNG `AppState.writePNG` writes, as bytes.
    static func pngData(_ image: CGImage, properties: [CFString: Any]?) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The longest file name a save takes, in UTF-8 bytes before the extension.
    static let fileNameByteLimit = 200

    /// A save's file name: letters, digits, spaces, `-`, `_` and `.`, ending in .png; sub-folders of the Agent folder are named
    /// with `/` (#515), each part by the same rule, so none is `..` or hidden.
    static func fileName(_ given: String?, default fallback: String, extension ext: String = "png") -> Result<String, AgentFolderRefusal> {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        var folders: [String] = []
        var given = given
        if let typed = given?.trimmingCharacters(in: .whitespacesAndNewlines), typed.contains("/") {
            var parts = typed.split(separator: "/", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let leaf = parts.removeLast()
            guard parts.count <= 8, parts.allSatisfy({ part in
                !part.isEmpty && !part.hasPrefix(".") && part.utf8.count <= fileNameByteLimit
                    && part.unicodeScalars.allSatisfy(allowed.contains)
            }), !leaf.isEmpty else {
                return .failure(AgentFolderRefusal("A sub-folder is named like a file: letters, digits, spaces, - _ and . only, "
                    + "not starting with a dot, as in maps/run 1/strain (at most 8 deep)."))
            }
            folders = parts
            given = leaf
        }
        var name = (given ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {   // the dataset's own name may hold any character: those outside the rule become _
            var kept = String.UnicodeScalarView()
            for scalar in fallback.unicodeScalars { kept.append(allowed.contains(scalar) ? scalar : Unicode.Scalar("_")) }
            name = String(kept)
            while name.hasPrefix(".") { name = "_" + String(name.dropFirst()) }
        }
        if name.lowercased().hasSuffix("." + ext) { name = String(name.dropLast(ext.count + 1)) }
        // A name the agent gives is refused when too long; the dataset's own is shortened (#310). macOS allows 255 bytes.
        if given?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            while name.utf8.count > fileNameByteLimit { name.removeLast() }
        } else if name.utf8.count > fileNameByteLimit {
            return .failure(AgentFolderRefusal("A file name is at most \(fileNameByteLimit) bytes before its extension."))
        }
        guard !name.isEmpty, !name.hasPrefix("."), name.unicodeScalars.allSatisfy(allowed.contains) else {
            return .failure(AgentFolderRefusal("A file name is letters, digits, spaces, - _ and . only (sub-folders with /), and "
                + "does not start with a dot."))
        }
        return .success((folders + [name + "." + ext]).joined(separator: "/"))
    }

    /// The place of a new file `name` (made by `fileName`) in the Agent folder `root`: refused when anything of that name exists,
    /// and its sub-folders made when missing (#515), each checked to stay inside the folder (a link that leads out is refused).
    static func newFileTarget(_ name: String, in root: URL) -> Result<URL, ToolRefusal> {
        let target = root.appendingPathComponent(name)
        // Any entry of that name, a link that leads nowhere included: `fileExists` follows links, so a dangling one would
        // read as free and the write would follow it out of the folder.
        guard (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil else {
            return .failure(ToolRefusal(status: 409, message: "\(name) exists in the Agent folder and is never replaced: choose another name."))
        }
        let parent = target.deletingLastPathComponent()
        guard name.contains("/") else { return .success(target) }
        let outside = ToolRefusal(status: 400, message: "\(name) would be outside the Agent folder; only folders inside it can be used.")
        // The deepest folder that exists already, links resolved, must be inside: a link part-way down the name never leads the
        // new folders out.
        var existing = parent
        while !FileManager.default.fileExists(atPath: existing.path), existing.path.count > root.path.count {
            existing = existing.deletingLastPathComponent()
        }
        guard folder.contains(AgentFolder.canonical(existing)) else { return .failure(outside) }
        do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) } catch {
            return .failure(ToolRefusal(status: 409, message: "The folder for \(name) could not be made in the Agent folder: "
                + error.localizedDescription))
        }
        guard folder.contains(AgentFolder.canonical(parent)) else { return .failure(outside) }
        return .success(AgentFolder.canonical(parent).appendingPathComponent(target.lastPathComponent))
    }

    /// Writes `data` as a NEW file of the Agent folder (O_EXCL: a name, or a link, that exists is never replaced or followed), behind
    /// "Let agents save results there". Answers the name written, or the refusal in words.
    static func saveNewFile(_ data: Data, named given: String?, default fallback: String,
                            extension ext: String) -> Result<String, ToolRefusal> {
        guard savesAllowed else {
            return .failure(ToolRefusal(status: 403, message: "Saving is off. Ask the person to turn on \"Let agents save results "
                + "there\" in \(AppName.display)'s Settings > Agents."))
        }
        guard let root = folder.url else { return .failure(ToolRefusal(status: 404, message: folder.missingMessage)) }
        let name: String
        switch fileName(given, default: fallback, extension: ext) {
        case .success(let made): name = made
        case .failure(let refusal): return .failure(ToolRefusal(status: 400, message: refusal.message))
        }
        let target: URL
        switch newFileTarget(name, in: root) {
        case .success(let made): target = made
        case .failure(let refusal): return .failure(refusal)
        }
        do { try data.write(to: target, options: .withoutOverwriting) } catch {
            return .failure(ToolRefusal(status: 409, message: "\(name) could not be written as a new file in the Agent folder: "
                + error.localizedDescription))
        }
        return .success(name)
    }
}
