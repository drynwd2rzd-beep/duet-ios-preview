import XCTest

final class DuetUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testNativeScreensDoNotUseWebViewsOrPageZoom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let group = app.buttons["thread.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 15))
        XCTAssertEqual(app.webViews.count, 0, "The main UI must be native")
        let before = group.frame
        let header = app.descendants(matching: .any)["home.header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        header.pinch(withScale: 1.5, velocity: 1)
        XCTAssertTrue(group.waitForExistence(timeout: 5), "Pinching the header should keep the home screen open")
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
        let ideas = app.tabBars.buttons["想法"]
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

    func testNativeBridgeConfiguration() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["想法"].waitForExistence(timeout: 12))
        app.tabBars.buttons["想法"].tap()
        app.buttons["open.settings"].tap()
        let accounts = app.buttons["settings.accounts"]
        XCTAssertTrue(accounts.waitForExistence(timeout: 6))
        accounts.tap()
        XCTAssertTrue(app.textFields["bridge.address"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.secureTextFields["bridge.token"].exists)
        XCTAssertTrue(app.buttons["bridge.connect"].exists)
        XCTAssertEqual(app.webViews.count, 0)
        attach(app, "Native Computer Connection")
    }

    func testSystemTabsRemainTappableAfterNavigatingAndPinning() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["thread.gpt"].waitForExistence(timeout: 12))
        app.buttons["thread.gpt"].swipeRight()
        let pin = app.buttons["置顶"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 4))
        pin.tap()
        for _ in 0..<3 {
            app.tabBars.buttons["想法"].tap()
            XCTAssertTrue(app.buttons["open.settings"].waitForExistence(timeout: 4))
            app.tabBars.buttons["聊天"].tap()
            app.buttons["thread.gpt"].tap()
            XCTAssertTrue(app.buttons["chat.options"].waitForExistence(timeout: 4))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        attach(app, "System Tabs After Pinning")
    }

    func testLatestMessageAndAvatarOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitest-history"]
        app.launch()
        XCTAssertTrue(app.buttons["thread.gpt"].waitForExistence(timeout: 12))
        app.buttons["thread.gpt"].tap()
        let latest = app.staticTexts["Latest test reply"]
        XCTAssertTrue(latest.waitForExistence(timeout: 6))
        XCTAssertTrue(latest.isHittable, "Opening a long conversation must start at the newest message")
        attach(app, "Latest Native Conversation")
        app.buttons["chat.options"].tap()
        XCTAssertTrue(app.buttons["chat.model.gpt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.background"].exists)
        attach(app, "Native Avatar Options")
        let clear = app.buttons["chat.clear-history"]
        for _ in 0..<3 where !clear.exists || !clear.isHittable { app.buttons["chat.background"].swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 4))
        clear.tap()
        app.buttons["清空记录"].tap()
        XCTAssertTrue(app.staticTexts["从一句话开始"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Latest test reply"].exists)
    }
}
