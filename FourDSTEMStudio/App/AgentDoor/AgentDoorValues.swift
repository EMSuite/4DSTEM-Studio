//
//  AgentDoorValues.swift
//  Role: the agent door's numbers as numbers (issue #515). `get_result_image` and `get_scan_map` are colour-mapped pictures
//        clipped to the display range (an agent once inverted viridis to read values back); these tools hand over the values
//        themselves: the displayed result's fields as Float32 (.npy, numpy's own format, or base64), and the Bragg vectors of
//        every scan position in one file (py4DSTEM's EMD, as the session file holds them, or CSV).
//

import Foundation
import ShellAgentDoor
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

extension Mac4DSTEMAgentDoor {
    /// The most bytes `get_result_values` answers inline as base64; a larger field goes to a .npy file.
    static let inlineValueByteLimit = 4 * 1024 * 1024

    static let valueTools: [AgentTool] = [
        AgentTool(name: "get_result_values", title: "Result values",
                  summary: "The numbers behind the displayed result, as Float32: the fields export_result data writes (for a "
                      + "virtual image or a strain map its values; for the phase map the phase label, verdict, distance, contrast "
                      + "and matched count of every position) and the result's quality fields. Rows are scan rows (y), columns "
                      + "scan columns (x); NaN where a position has no value. format npy saves numpy's .npy into the Agent folder "
                      + "(needs \"Let agents save results there\"; never replaces a file; np.load reads it); base64 answers the "
                      + "raw little-endian bytes inline, up to 4 MB. Without field it answers the field list.",
                  input: .window,
                  parameters: [
                      AgentParameter("field", .text, summary: "A field's name from the list this tool answers without one."),
                      AgentParameter("format", .choice(["npy", "base64"]), summary: "npy (default) or base64."),
                      AgentParameter("name", .text, summary: "For npy: the file name, sub-folders with /; .npy is added."),
                  ]) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            let fields = state.agentValueFields
            guard !fields.isEmpty else {
                return .refusal(status: 404, message: "The displayed result has no numbers to give (none, or a colour picture).")
            }
            let listing = fields.map { ["name": $0.name, "units": $0.units, "width": $0.width, "height": $0.height] as [String: Any] }
            guard let wanted = call.arguments["field"] else { return .json(["fields": listing]) }
            guard let field = fields.first(where: { $0.name == wanted }) else {
                return .refusal(status: 404, message: "No field \(wanted); this result has " + fields.map(\.name).joined(separator: ", ") + ".")
            }
            var answer: [String: Any] = ["field": field.name, "units": field.units, "dtype": "float32", "byte_order": "little",
                                         "shape": [field.height, field.width]]
            if call.arguments["format"] == "base64" {
                let bytes = field.pixels.count * MemoryLayout<Float>.size
                guard bytes <= inlineValueByteLimit else {
                    return .refusal(status: 413, message: "\(field.name) is \(bytes) bytes, more than base64 takes "
                        + "(\(inlineValueByteLimit)); use format npy.")
                }
                answer["data_base64"] = littleEndianBytes(field.pixels).base64EncodedString()
                return .json(answer)
            }
            let stem = state.exportBaseName + "_" + String(field.name.map { $0.isLetter || $0.isNumber ? $0 : "_" })
            switch saveNewFile(npyData(field.pixels, height: field.height, width: field.width),
                               named: call.arguments["name"], default: stem, extension: "npy") {
            case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
            case .success(let name):
                state.statusText = "An agent saved the values of \(field.name) → \(name) in the Agent folder."
                answer["saved"] = name
                return .json(answer)
            }
        },
        AgentTool(name: "export_bragg_vectors", title: "Export Bragg vectors",
                  summary: "Writes the detected disks of every scan position in one file of the Agent folder: h5 (default), "
                      + "py4DSTEM's BraggVectors in EMD 1.0, the form the session file keeps them in (py4DSTEM.read opens it); or "
                      + "csv, one row per disk: scan_x, scan_y, x_px, y_px (detector pixels, as get_detected_disks) and "
                      + "intensity. Needs a whole-scan detection whose settings are current (run_task in Disks) and \"Let agents "
                      + "save results there\"; never replaces a file.",
                  input: .window,
                  parameters: [
                      AgentParameter("format", .choice(["h5", "csv"]), summary: "h5 (default) or csv."),
                      AgentParameter("name", .text, summary: "The file name, sub-folders with /; the extension is added."),
                  ],
                  acts: true) { call in
            guard let state = call.window?.state as? AppState else { return notAWindow }
            guard !state.agentBusy else { return busyRefusal }
            guard let descriptor = state.descriptor else { return .refusal(status: 404, message: "This window has no dataset open.") }
            guard let vectors = state.resultPresentation.braggVectors else {
                return .refusal(status: 409, message: "No disks are detected over the scan yet (run_task in Disks).")
            }
            guard !state.diskDetectionSettingsAreStale else {
                return .refusal(status: 409, message: "The disk settings changed since the scan was detected; run_task in Disks again "
                    + "so the file matches the settings.")
            }
            let fallback = state.exportBaseName + "_bragg_vectors"
            if call.arguments["format"] == "csv" {
                switch saveNewFile(braggCSV(vectors), named: call.arguments["name"], default: fallback, extension: "csv") {
                case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
                case .success(let name):
                    state.statusText = "An agent exported the Bragg vectors → \(name) in the Agent folder."
                    return .json(["saved": name, "positions": vectors.peaks.count, "disks": vectors.totalPeakCount])
                }
            }
            let target: URL
            switch newAgentFolderTarget(call.arguments["name"], default: fallback, extension: "h5") {
            case .failure(let refusal): return .refusal(status: refusal.status, message: refusal.message)
            case .success(let url): target = url
            }
            let calibration = state.sessionPixelCalibration(descriptor: descriptor)
            let specification = state.loadedView.specification
            do {
                try writeNewFile(at: target) { scratch in
                    try BraggVectorEMDWriter.write(vectors: vectors, qWidth: descriptor.qx, qHeight: descriptor.qy,
                                                   calibration: calibration, to: scratch, loadSpecification: specification)
                }
            } catch {
                state.agentExportFailed(target.lastPathComponent, error)
                return .refusal(status: 500, message: "\(target.lastPathComponent) was not written: \(error.localizedDescription)")
            }
            state.agentLastExport = AgentExportOutcome(file: target.lastPathComponent, state: .written)
            state.statusText = "An agent exported the Bragg vectors → \(target.lastPathComponent) in the Agent folder."
            return .json(["saved": folder.relativePath(of: target), "positions": vectors.peaks.count,
                          "disks": vectors.totalPeakCount])
        },
    ]

    /// Float32 little-endian bytes (every Mac is little-endian; said, not assumed, in the .npy header and the answer).
    nonisolated static func littleEndianBytes(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    /// numpy's .npy format 1.0 (numpy.lib.format): the magic, the version, a header dict padded with spaces to a multiple of
    /// 64 bytes and ending in a newline, then the C-order data.
    nonisolated static func npyData(_ values: [Float], height: Int, width: Int) -> Data {
        var header = "{'descr': '<f4', 'fortran_order': False, 'shape': (\(height), \(width)), }"
        let preamble = 10   // \x93NUMPY, two version bytes, two length bytes
        while (preamble + header.utf8.count + 1) % 64 != 0 { header += " " }
        header += "\n"
        var data = Data([0x93]) + Data("NUMPY".utf8) + Data([1, 0])
        let length = UInt16(header.utf8.count)
        data.append(contentsOf: [UInt8(length & 0xFF), UInt8(length >> 8)])
        data.append(Data(header.utf8))
        data.append(littleEndianBytes(values))
        return data
    }

    /// One row per disk: scan_x, scan_y, x_px, y_px, intensity; positions row-major, as the vectors hold them.
    static func braggCSV(_ vectors: BraggVectors) -> Data {
        var text = "scan_x,scan_y,x_px,y_px,intensity\n"
        for (index, peaks) in vectors.peaks.enumerated() {
            let x = index % max(vectors.scanWidth, 1), y = index / max(vectors.scanWidth, 1)
            for peak in peaks {
                text += "\(x),\(y),\(numberText(Double(peak.x))),\(numberText(Double(peak.y))),\(numberText(Double(peak.intensity)))\n"
            }
        }
        return Data(text.utf8)
    }

    /// get_detected_disks over a rectangle of scan positions (#515): from the whole-scan detection, at most 10 000 positions.
    static func peaksInRectangle(of state: AppState, x0: Int, y0: Int, x1: Int, y1: Int) -> AgentToolOutput {
        guard let vectors = state.resultPresentation.braggVectors else {
            return .refusal(status: 409, message: "A rectangle reads the whole-scan detection, and there is none yet (run_task in Disks).")
        }
        let xs = min(x0, x1)...max(x0, x1), ys = min(y0, y1)...max(y0, y1)
        guard xs.lowerBound >= 0, ys.lowerBound >= 0, xs.upperBound < vectors.scanWidth, ys.upperBound < vectors.scanHeight else {
            return .refusal(status: 400, message: "The scan is \(vectors.scanWidth) × \(vectors.scanHeight): x is 0...\(vectors.scanWidth - 1), "
                + "y is 0...\(vectors.scanHeight - 1).")
        }
        guard xs.count * ys.count <= 10_000 else {
            return .refusal(status: 413, message: "At most 10 000 positions per call; for the whole scan use export_bragg_vectors.")
        }
        var positions: [[String: Any]] = []
        for y in ys {
            for x in xs {
                let peaks = vectors.peaks[y * vectors.scanWidth + x]
                positions.append(["x": x, "y": y, "disks": peaks.map { peak in
                    ["x": AgentJSON.number(peak.x), "y": AgentJSON.number(peak.y), "intensity": AgentJSON.number(peak.intensity)]
                }])
            }
        }
        return .json(["coordinates": "detector pixels: x to the right, y down, (0, 0) the centre of the top-left pixel",
                      "settings_changed_since_run": state.diskDetectionSettingsAreStale, "positions": positions])
    }
}

/// One field `get_result_values` gives.
struct AgentValueField {
    let name: String
    let units: String
    let width: Int
    let height: Int
    let pixels: [Float]
}

extension AppState {
    /// The displayed result's numeric fields, as the data export writes them, then its quality fields.
    var agentValueFields: [AgentValueField] {
        var fields: [AgentValueField] = []
        let maps = phaseMapDataExportMaps() ?? productDataExportMap().map { [$0] } ?? []
        for map in maps {
            fields.append(AgentValueField(name: map.kind, units: map.valueUnits, width: map.width, height: map.height, pixels: map.pixels))
        }
        for quality in displayedProduct?.qualityFields ?? [] where !fields.contains(where: { $0.name == quality.name }) {
            fields.append(AgentValueField(name: quality.name, units: quality.units, width: quality.image.width,
                                          height: quality.image.height, pixels: quality.image.pixels))
        }
        return fields
    }
}
