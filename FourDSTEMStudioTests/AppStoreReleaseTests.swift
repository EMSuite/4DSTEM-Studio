//
//  AppStoreReleaseTests.swift
//  One tag, two builds (mac4DSTEM#121): tools/release.sh builds the Developer ID DMG and, with --store, the App Store
//  package. The export options and the script's guards are files a later edit can quietly break; these read them.
//

import DSTEMCore
import ShellAgentDoor
import XCTest

final class AppStoreReleaseTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Mutation: method back to "developer-id", destination "upload", or another team - red.
    func testTheStoreExportOptionsExportAnAppStorePackageForTheTeam() throws {
        let url = root.appendingPathComponent("tools/release/ExportOptions-AppStore.plist")
        let options = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            as? [String: Any])
        XCTAssertEqual(options["method"] as? String, "app-store-connect")
        XCTAssertEqual(options["destination"] as? String, "export", "the export never uploads; --upload is its own step")
        XCTAssertEqual(options["teamID"] as? String, "3B8SMSSAX4")
        XCTAssertEqual(options["signingStyle"] as? String, "automatic")
    }

    /// Mutation: drop a product check from build-app-store.sh, or let release.sh upload without --upload - red.
    func testTheStoreBuildChecksItsProductAndUploadsOnlyWhenAsked() throws {
        let build = try String(contentsOf: root.appendingPathComponent("tools/release/build-app-store.sh"), encoding: .utf8)
        for check in ["MACEM_STORE_BUILD=YES", "pkgutil --check-signature", "com.apple.security.app-sandbox",
                      "get-task-allow", "PrivacyInfo.xcprivacy", "ITSAppUsesNonExemptEncryption", "Sparkle.framework",
                      "assert_mac4dstem_bundle_arm64_only", "ExportOptions-AppStore.plist"] {
            XCTAssertTrue(build.contains(check), "build-app-store.sh no longer checks \(check)")
        }
        XCTAssertFalse(build.contains("altool"), "the build step uploads nothing")

        let release = try String(contentsOf: root.appendingPathComponent("tools/release.sh"), encoding: .utf8)
        let uploads = release.components(separatedBy: "--upload-app").count - 1
        XCTAssertEqual(uploads, 1)
        let guardLine = try XCTUnwrap(release.range(of: "if (( UPLOAD == 1 )); then"))
        let uploadLine = try XCTUnwrap(release.range(of: "--upload-app"))
        XCTAssertLessThan(guardLine.lowerBound, uploadLine.lowerBound, "the upload sits behind --upload")
        XCTAssertTrue(release.contains("describe --exact-match --tags HEAD"), "both flavours build from a release tag")
    }

    /// App Review refuses "Mac" in an App Store app's name (guideline 5.2.5, 5.2.0 rejected 16 Nov 2026). The store build is
    /// "4DSTEM Studio", and since 5.4.3 the website download is too (#496). Mutation: "mac" back in either name, PRODUCT_NAME
    /// back to the target name, or the module name left to follow the product - red.
    func testTheStoreBuildCarriesANameWithoutMac() throws {
        let config = try String(contentsOf: root.appendingPathComponent("Config/Version.xcconfig"), encoding: .utf8)
        func setting(_ key: String) -> String? {
            config.split(separator: "\n").first { $0.hasPrefix("\(key) = ") }.map { String($0.dropFirst(key.count + 3)) }
        }
        XCTAssertEqual(setting("MACEM_APP_NAME_YES"), "4DSTEM Studio")
        XCTAssertEqual(setting("MACEM_APP_NAME_NO"), "4DSTEM Studio", "the website download carries the same name (#496)")
        XCTAssertFalse(try XCTUnwrap(setting("MACEM_APP_NAME_YES")).lowercased().contains("mac"))
        XCTAssertFalse(try XCTUnwrap(setting("MACEM_APP_NAME_NO")).lowercased().contains("mac"))

        let project = try String(contentsOf: root.appendingPathComponent("FourDSTEMStudio.xcodeproj/project.pbxproj"), encoding: .utf8)
        let appConfigurations = project.components(separatedBy: "isa = XCBuildConfiguration;")
            .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = \"$(MACEM_APP_ID)\";") }
        XCTAssertEqual(appConfigurations.count, 3, "Debug, Release and Develop of the app target")
        for configuration in appConfigurations {
            XCTAssertTrue(configuration.contains("PRODUCT_NAME = \"$(MACEM_APP_NAME_$(MACEM_STORE_BUILD))\";"))
            XCTAssertTrue(configuration.contains("PRODUCT_MODULE_NAME = FourDSTEMStudio;"), "the module is FourDSTEMStudio since 5.5.0 (#510)")
            XCTAssertTrue(configuration.contains("INFOPLIST_KEY_CFBundleDisplayName = \"$(PRODUCT_NAME)\";"))
        }
        XCTAssertTrue(config.contains("MACEM_APP_ID = com.mac4dstem.mac4DSTEM"), "the bundle identifier never changes")

        let build = try String(contentsOf: root.appendingPathComponent("tools/release/build-app-store.sh"), encoding: .utf8)
        for check in ["MACEM_APP_NAME_YES", "CFBundleName CFBundleDisplayName", "*mac*", "CFBundleIdentifier"] {
            XCTAssertTrue(build.contains(check), "build-app-store.sh no longer checks \(check)")
        }
    }

    /// The name a sentence on screen uses comes from the bundle; a host without one falls back to the project's name.
    func testTheAppNameComesFromTheBundle() {
        XCTAssertEqual(AppName.display(from: ["CFBundleDisplayName": "4DSTEM Studio", "CFBundleName": "x"]), "4DSTEM Studio")
        XCTAssertEqual(AppName.display(from: ["CFBundleName": "4DSTEM Studio"]), "4DSTEM Studio")
        XCTAssertEqual(AppName.display(from: ["CFBundleDisplayName": ""]), "4DSTEM Studio")
        XCTAssertEqual(AppName.display(from: nil), "4DSTEM Studio")
        XCTAssertEqual(AppName.display, "4DSTEM Studio", "the test host is the website flavour, named 4DSTEM Studio (#496)")
    }

    /// The website download's running bundle says 4DSTEM Studio, and Sparkle's SUBundleName names the file an update installs
    /// to (#496, #497). Mutation: MACEM_APP_NAME_NO back to mac4DSTEM, or SUBundleName dropped or misspelt - red.
    func testTheWebsiteBuildIsNamed4DSTEMStudio() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["CFBundleName"] as? String, "4DSTEM Studio")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "4DSTEM Studio")
        XCTAssertEqual(Bundle.main.bundleURL.lastPathComponent, "4DSTEM Studio.app")
        XCTAssertEqual(info["SUBundleName"] as? String, "4DSTEM Studio")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.mac4dstem.mac4DSTEM", "installed copies keep updating")
    }

    /// The store build's door registers as one word: its name "4DSTEM Studio" has a space, and the copied connection command
    /// split there (#477, fixed in MacEMUI 0.12.3). Mutation: MacEMUI back to 0.12.2 (no serverName), or the name lower-cased
    /// as is - red.
    @MainActor
    func testTheStoreNameRegistersAsOneWord() throws {
        let config = try String(contentsOf: root.appendingPathComponent("Config/Version.xcconfig"), encoding: .utf8)
        let storeName = try XCTUnwrap(config.split(separator: "\n").first { $0.hasPrefix("MACEM_APP_NAME_YES = ") }
            .map { String($0.dropFirst("MACEM_APP_NAME_YES = ".count)) })
        let suite = "AppStoreReleaseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let door = AgentDoor(appName: storeName, appVersion: "0", preferredPort: 47811, defaults: defaults)
        XCTAssertEqual(door.serverName, "4dstem-studio")
        XCTAssertFalse(door.serverName.contains(" "))
    }
}
