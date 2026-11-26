//
//  FeedbackLinks.swift
//  Role: where the Help menu goes (#487): the app's documentation on the website (first, ⌘?), the tutorials, the support page
//        and Send Feedback. Every address is a page EMSuite/website serves (docs/4dstem-studio/index.html, docs/tasks/index.html,
//        support.html); the welcome window's Tutorials link is the same address. Feedback is an email the person writes and sends from their
//        own mail app, addressed to the project, with the app and macOS versions prefilled so a report names its build. The app
//        itself sends nothing (the privacy label stays "Data Not Collected").
//

import DSTEMCore
import Foundation

nonisolated enum FeedbackLinks {
    static let address = "mail@mac4dstem.com"
    static let support = URL(string: "https://mac4dstem.com/support.html")
    /// The app's documentation, the Help menu's first item (⌘?), in place of the system's Help book item.
    static let help = URL(string: "https://mac4dstem.com/docs/4dstem-studio/")
    /// One page per task, each in a few steps: the tutorials index, shared with Electron Microscopy Studio.
    static let tutorials = URL(string: "https://mac4dstem.com/docs/tasks/")

    /// "5.2.1 (41)" from the bundle; "unknown" for a bundle without a version (a test host).
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "unknown" }
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    /// The `mailto:` link: subject and a first line with the two versions, then room to write. Pure, so it is tested.
    static func mail(appVersion: String, systemVersion: String) -> URL? {
        var link = URLComponents()
        link.scheme = "mailto"
        link.path = address
        link.queryItems = [
            URLQueryItem(name: "subject", value: "\(AppName.display) feedback"),
            URLQueryItem(name: "body", value: "\n\n\(AppName.display) \(appVersion), macOS \(systemVersion)"),
        ]
        return link.url
    }

    static var mail: URL? {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return mail(appVersion: appVersion, systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }
}
