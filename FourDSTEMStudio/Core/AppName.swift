//
//  AppName.swift
//  Role: the app's name as the person sees it, read from the bundle. Both builds are "4DSTEM Studio": App Review refuses
//        "Mac" in an app's name (guideline 5.2.5, 16 Nov 2026), and the website build followed in 5.4.3 (#496). The names
//        are set in Config/Version.xcconfig, so a sentence on screen names the build the person runs. Files the app writes
//        keep "mac4DSTEM" as their authoring program: that is the project's name, which readers and provenance rely on.
//

import Foundation

public nonisolated enum AppName {
    /// "4DSTEM Studio": CFBundleDisplayName, else CFBundleName, else the project's name. Only an app's own
    /// bundle names it: under `swift test` the main bundle is the xctest tool, and in a Quick Look extension the appex.
    public static let display: String = Bundle.main.bundleURL.pathExtension == "app"
        ? display(from: Bundle.main.infoDictionary) : fallback

    /// Pure, so it is tested.
    public static func display(from info: [String: Any]?) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info?[key] as? String, !name.isEmpty { return name }
        }
        return fallback
    }

    /// The name when no bundle gives one.
    static let fallback = "4DSTEM Studio"
}
