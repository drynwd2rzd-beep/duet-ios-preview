import XCTest

final class DuetUITests: XCTestCase {
    func testNativeScreensDoNotUseWebViewsOrPageZoom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let group = app.buttons["thread.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0, "The main UI must be native")
        let before = group.frame
        app.windows.firstMatch.pinch(withScale: 1.5, velocity: 1)
        let after = group.frame
        XCTAssertEqual(before.width, after.width, accuracy: 1, "Pinching the home page must not scale its UI")
        attach(app, "Native Chats")
        group.tap()
        let field = app.descendants(matching: .any)["message.input"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertEqual(app.webViews.count, 0)
        field.tap()
        app.typeText("Native hello")
        let send = app.buttons["message.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        attach(app, "Native Chat Composer")
    }

    func testNativeIdeasAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let ideas = app.buttons["tab.ideas"]
        XCTAssertTrue(ideas.waitForExistence(timeout: 12))
        ideas.tap()
        attach(app, "Native Ideas")
        app.buttons["open.settings"].tap()
        let appearance = app.buttons["settings.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 6))
        XCTAssertEqual(app.webViews.count, 0)
        attach(app, "Native Settings")
        appearance.tap()
        XCTAssertTrue(app.segmentedControls["appearance.mode"].waitForExistence(timeout: 6))
        attach(app, "Native Appearance")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
