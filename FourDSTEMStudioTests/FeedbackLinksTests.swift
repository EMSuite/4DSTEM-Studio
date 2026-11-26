// The Help menu (#487): the documentation and tutorials on the website, the support page, and Send Feedback, an email the
// person sends themselves, to the project's address, naming the build. The addresses are pages EMSuite/website serves
// (docs/4dstem-studio/index.html, docs/tasks/index.html, support.html), checked against that repository when written.
// Red before #487: no help or tutorials address, and the menu had only Support and Send Feedback.

import XCTest
@testable import FourDSTEMStudio

final class FeedbackLinksTests: XCTestCase {
    /// Mutation: another address, or the versions dropped from the body - red.
    func testFeedbackIsAnEmailToTheProjectThatNamesTheBuild() throws {
        let url = try XCTUnwrap(FeedbackLinks.mail(appVersion: "5.2.1 (41)", systemVersion: "26.1.0"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "mail@mac4dstem.com")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "subject" }?.value, "4DSTEM Studio feedback")
        let body = try XCTUnwrap(parts.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.hasSuffix("4DSTEM Studio 5.2.1 (41), macOS 26.1.0"), body)
        XCTAssertTrue(body.hasPrefix("\n\n"), "room to write above the versions")
    }

    func testSupportIsTheWebsitesSupportPage() {
        XCTAssertEqual(FeedbackLinks.support?.absoluteString, "https://mac4dstem.com/support.html")
        XCTAssertNotNil(FeedbackLinks.mail)
    }

    /// Mutation: another page, or an address the website does not serve - red.
    func testHelpAndTutorialsAreTheWebsitesPages() {
        XCTAssertEqual(FeedbackLinks.help?.absoluteString, "https://mac4dstem.com/docs/4dstem-studio/")
        XCTAssertEqual(FeedbackLinks.tutorials?.absoluteString, "https://mac4dstem.com/docs/tasks/")
    }

    /// The menu's order (Help with ⌘?, Tutorials, then Support and Send Feedback) and the welcome window's Tutorials link.
    func testTheMenuAndTheWelcomeWindowAreWired() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("FourDSTEMStudio/App/FourDSTEMStudioApp.swift"), encoding: .utf8)
        let help = try XCTUnwrap(app.range(of: "Button(\"\\(AppName.display) Help\") { if let url = FeedbackLinks.help { openURL(url) } }\n                .keyboardShortcut(\"?\", modifiers: .command)"))
        let tutorials = try XCTUnwrap(app.range(of: "Button(\"Tutorials\") { if let url = FeedbackLinks.tutorials { openURL(url) } }"))
        let support = try XCTUnwrap(app.range(of: "Button(\"\\(AppName.display) Support\")"))
        XCTAssertTrue(help.lowerBound < tutorials.lowerBound && tutorials.lowerBound < support.lowerBound)
        let welcome = try String(contentsOf: root.appendingPathComponent("FourDSTEMStudio/UI/WorkspaceView.swift"), encoding: .utf8)
        XCTAssertTrue(welcome.contains("Link(destination: tutorials)"))
        XCTAssertTrue(welcome.contains("accessibilityIdentifier(\"welcome.tutorials\")"))
    }
}
