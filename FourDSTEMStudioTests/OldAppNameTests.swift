//
//  OldAppNameTests.swift
//  The app is 4DSTEM Studio in both builds since 5.4.3 (#496): no text the person reads names it mac4DSTEM.
//

import XCTest

final class OldAppNameTests: XCTestCase {
    /// Every string literal in the app's sources that says "mac4DSTEM", on a line that is not a comment, is one of the kept
    /// places below: identifiers, provenance that readers rely on, or text that is not shown. Anything else says the app's
    /// name with AppName.display. Mutation: put "mac4DSTEM" back into a sentence on screen, such as the update check's help
    /// - red.
    func testNoTextOnScreenNamesTheOldApp() throws {
        let kept: [(file: String, text: String)] = [
            ("AppState.swift", "mac4DSTEM analysis run"),                       // ProcessInfo activity reason, not shown
            ("ReplayRun.swift", "mac4DSTEM promote run"),                       // ProcessInfo activity reason, not shown
            ("BraggVectorEMDWriter.swift", "mac4DSTEM"),                         // EMD authoring program (provenance)
            ("CalibratedDataCubeWriter.swift", "mac4DSTEM"),                     // EMD authoring program (provenance)
            ("SessionSidecarWriting.swift", "mac4DSTEM"),                        // EMD authoring program (provenance)
            ("RQRotationConvention.swift", "mac4DSTEM"),                         // reads files this app wrote under its old name
            ("RQRotationConvention.swift", "Sign unrecorded (exported by mac4DSTEM"),   // names the old version, by date
            ("EDXOpening.swift", "mac4DSTEM"),                                   // EDS export creator (provenance)
            ("EDXOpening.swift", "mac4DSTEM EDS room"),                          // EDS export provenance
            ("EDXOpening.swift", "mac4DSTEM EDS regions"),                       // EDS export title (provenance)
            ("LearnedDiskDetector.swift", "mac4DSTEM Core is arm64-only"),       // a compile-time #error
            ("FigureExport.swift", "mac4DSTEM"),                                 // TIFF Software tag (provenance)
            ("FigureRendering.swift", "mac4DSTEM"),                              // PDF Creator (provenance)
            ("ResultExport+Rendering.swift", "mac4DSTEM"),                       // PNG Software tag (provenance)
            ("TrainedModelStore.swift", "mac4DSTEM/DiskDetectorModels"),         // the Application Support folder, kept
            ("CompositionByClass.swift", "# mac4DSTEM Spectroscopy"),            // CSV header (provenance)
        ]
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("FourDSTEMStudio")
        let literal = #/"((?:[^"\\]|\\.)*)"/#
        var found: [String] = [], files = 0
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in walker where url.pathExtension == "swift" {
            files += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.drop(while: { $0 == " " })
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { continue }
                for match in line.matches(of: literal) {
                    let value = String(match.1)
                    guard value.contains("mac4DSTEM"), !value.hasPrefix("com.mac4dstem.") else { continue }
                    // The bare name only as the whole literal; a longer kept text as the literal's start (its interpolations vary).
                    if kept.contains(where: { $0.file == url.lastPathComponent
                        && (value == $0.text || ($0.text != "mac4DSTEM" && value.hasPrefix($0.text))) }) { continue }
                    found.append("\(url.lastPathComponent):\(number + 1): \(value)")
                }
            }
        }
        XCTAssertGreaterThan(files, 100, "the app's sources were found")
        XCTAssertEqual(found, [], "text on screen that names the old app; use AppName.display")
    }
}
