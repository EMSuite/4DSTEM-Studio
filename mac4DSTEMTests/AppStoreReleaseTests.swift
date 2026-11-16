//
//  AppStoreReleaseTests.swift
//  One tag, two builds (mac4DSTEM#121): tools/release.sh builds the Developer ID DMG and, with --store, the App Store
//  package. The export options and the script's guards are files a later edit can quietly break; these read them.
//

import DSTEMCore
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
    /// "4DSTEM Studio"; the website download keeps mac4DSTEM. Mutation: "mac" back in the store name, PRODUCT_NAME back to
    /// the target name, or the module name left to follow the product - red.
    func testTheStoreBuildCarriesANameWithoutMac() throws {
        let config = try String(contentsOf: root.appendingPathComponent("Config/Version.xcconfig"), encoding: .utf8)
        func setting(_ key: String) -> String? {
            config.split(separator: "\n").first { $0.hasPrefix("\(key) = ") }.map { String($0.dropFirst(key.count + 3)) }
        }
        XCTAssertEqual(setting("MACEM_APP_NAME_YES"), "4DSTEM Studio")
        XCTAssertEqual(setting("MACEM_APP_NAME_NO"), "mac4DSTEM", "the website download keeps its name")
        XCTAssertFalse(try XCTUnwrap(setting("MACEM_APP_NAME_YES")).lowercased().contains("mac"))

        let project = try String(contentsOf: root.appendingPathComponent("mac4DSTEM.xcodeproj/project.pbxproj"), encoding: .utf8)
        let appConfigurations = project.components(separatedBy: "isa = XCBuildConfiguration;")
            .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = \"$(MACEM_APP_ID)\";") }
        XCTAssertEqual(appConfigurations.count, 3, "Debug, Release and Develop of the app target")
        for configuration in appConfigurations {
            XCTAssertTrue(configuration.contains("PRODUCT_NAME = \"$(MACEM_APP_NAME_$(MACEM_STORE_BUILD))\";"))
            XCTAssertTrue(configuration.contains("PRODUCT_MODULE_NAME = mac4DSTEM;"), "sessions and tests keep the module")
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
        XCTAssertEqual(AppName.display(from: ["CFBundleDisplayName": ""]), "mac4DSTEM")
        XCTAssertEqual(AppName.display(from: nil), "mac4DSTEM")
        XCTAssertEqual(AppName.display, "mac4DSTEM", "the test host is the website flavour")
    }
}
