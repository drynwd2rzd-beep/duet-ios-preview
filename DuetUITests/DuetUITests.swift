import XCTest

final class DuetUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    func testNativeScreensDoNotUseWebViewsOrPageZoom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let group = app.buttons["thread.group"]
        XCTAssertTrue(group.waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The matte home dock must not overlap a system glass tab bar")
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
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The home tab bar must be hidden in a conversation")
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
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Ideas must use only the matte home dock")
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
        XCTAssertTrue(app.buttons["tab.ideas"].waitForExistence(timeout: 12))
        app.buttons["tab.ideas"].tap()
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
        let gpt = app.buttons["thread.gpt"], claude = app.buttons["thread.claude"]
        let moved = NSPredicate { _, _ in gpt.exists && claude.exists && gpt.frame.minY < claude.frame.minY }
        expectation(for: moved, evaluatedWith: nil); waitForExpectations(timeout: 5)
        for label in ["取消置顶", "置顶", "取消置顶", "置顶"] {
            gpt.swipeRight()
            let action = app.buttons[label].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 4)); action.tap()
            let closed = NSPredicate { _, _ in !app.buttons[label].firstMatch.exists }
            expectation(for: closed, evaluatedWith: nil); waitForExpectations(timeout: 5)
        }
        for _ in 0..<3 {
            app.buttons["tab.ideas"].tap()
            XCTAssertTrue(app.buttons["open.settings"].waitForExistence(timeout: 4))
            app.buttons["tab.chats"].tap()
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
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The chat must not keep the home tab bar below its composer")
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

    func testReplyFollowsAboveComposerWithKeyboardVisible() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitest-history", "--uitest-replies"]
        app.launch()
        XCTAssertTrue(app.buttons["thread.gpt"].waitForExistence(timeout: 12))
        app.buttons["thread.gpt"].tap()
        let input = app.descendants(matching: .any)["message.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); app.typeText("reply test")
        let send = app.buttons["message.send"]; send.tap()
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Stream reply complete")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 12))
        XCTAssertTrue(reply.isHittable, "A new reply must remain visible above the keyboard without manually scrolling")
        XCTAssertLessThanOrEqual(reply.frame.maxY, send.frame.minY + 12)
        attach(app, "Reply Follow With Keyboard")
    }

    func testPhotoMenuPresentsSystemPicker() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["thread.gpt"].waitForExistence(timeout: 12)); app.buttons["thread.gpt"].tap()
        app.buttons["message.attach"].tap()
        let photos = app.buttons["照片"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 5)); photos.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "取消")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "The menu must present the native photo picker")
        attach(app, "Native Photo Picker"); cancel.tap()
    }

    func testSendingAnotherMessageDoesNotBecomeStop() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitest-replies", "--uitest-hold-replies"]
        app.launch()
        XCTAssertTrue(app.buttons["thread.gpt"].waitForExistence(timeout: 12)); app.buttons["thread.gpt"].tap()
        let input = app.descendants(matching: .any)["message.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); app.typeText("one")
        let send = app.buttons["message.send"]; send.tap()
        XCTAssertTrue(app.staticTexts["one"].waitForExistence(timeout: 5))
        XCTAssertEqual(send.label, "停止回复")
        app.typeText("two")
        XCTAssertEqual(send.label, "发送消息", "A draft must send instead of cancelling the active reply")
        send.tap()
        XCTAssertTrue(app.staticTexts["two"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["one"].exists)
        XCTAssertFalse(app.staticTexts["已停止"].exists)
    }

    func testWallpaperContinuesBehindHeaderAndComposer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitest-history", "--uitest-wallpaper"]
        app.launch()
        XCTAssertTrue(app.buttons["thread.gpt"].waitForExistence(timeout: 12)); app.buttons["thread.gpt"].tap()
        XCTAssertTrue(app.buttons["chat.options"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        attach(app, "Continuous Wallpaper Header And Composer")
    }

    func testFontImportPresentsNativeDocumentPicker() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["tab.ideas"].waitForExistence(timeout: 12)); app.buttons["tab.ideas"].tap()
        app.buttons["open.settings"].tap(); app.buttons["settings.appearance"].tap(); app.buttons["font.import"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Cancel", "取消")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Font import must open a native file picker that accepts font data")
        attach(app, "Native Font Document Picker"); cancel.tap()
    }
}
