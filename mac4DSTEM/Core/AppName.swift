//
//  AppName.swift
//  Role: the app's name as the person sees it, read from the bundle. The website build is "mac4DSTEM"; the App Store build
//        is "4DSTEM Studio", because App Review refuses "Mac" in an app's name (guideline 5.2.5, 16 Nov 2026). Both names
//        are set in Config/Version.xcconfig, so a sentence on screen names the build the person runs. Files the app writes
//        keep "mac4DSTEM" as their authoring program: that is the project's name, which readers and provenance rely on.
//

import Foundation

public nonisolated enum AppName {
    /// "mac4DSTEM" or "4DSTEM Studio": CFBundleDisplayName, else CFBundleName, else the project's name (a test host
    /// without either key).
    public static let display: String = display(from: Bundle.main.infoDictionary)

    /// Pure, so it is tested.
    public static func display(from info: [String: Any]?) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info?[key] as? String, !name.isEmpty { return name }
        }
        return "mac4DSTEM"
    }
}
