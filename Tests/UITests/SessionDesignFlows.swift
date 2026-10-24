import XCTest

final class SessionDesignFlows: XCTestCase {
    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures", "--session-design-fixtures", "--workspace", "chat", "--light-appearance-fixtures"] + extra
        app.launch(); return app
    }

    @MainActor private func expectDraft(_ text: String, in composer: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let committed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: composer)
        XCTAssertEqual(XCTWaiter.wait(for: [committed], timeout: 5), .completed, "The complete draft must be committed before another action", file: file, line: line)
    }

    @MainActor func testSessionSheetPreservesDraftAndMuteOverridesNotifications() {
        let app = launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        composer.tap(); composer.typeText("Keep this unsent draft")
        expectDraft("Keep this unsent draft", in: composer)
        app.buttons["chat.actions"].tap()
        let done = app.buttons["chat.session.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        let pin = app.buttons["chat.session.pin"]
        pin.tap(); XCTAssertEqual(pin.label, "Unpin")
        let mute = app.buttons["chat.session.mute"]
        mute.tap(); XCTAssertEqual(mute.label, "Unmute")
        XCTAssertFalse(app.switches["chat.session.notify"].isEnabled)
        done.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Keep this unsent draft")
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Session sheet preserves draft"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testToolSummaryExposesSelectableFailureDetails() {
        let app = launch()
        let summary = app.buttons["chat.tools.summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        if !summary.isHittable { app.scrollViews.firstMatch.swipeDown() }
        summary.tap()
        let failure = app.buttons["chat.tool.session_build"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        if !failure.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertEqual(failure.value as? String, "failure")
        failure.tap()
        XCTAssertTrue(app.staticTexts["chat.tool.details"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["chat.tool.details"].label.contains("synthetic QA output"))
        app.buttons["chat.tool.copy"].tap()
        XCTAssertEqual(app.buttons["chat.tool.copy"].label, "Copied")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Inspectable tool failure"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["chat.tool.done"].tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
    }

    @MainActor func testContextCompactionAndForkUseExistingSessionServices() {
        let app = launch()
        XCTAssertTrue(app.buttons["chat.actions"].waitForExistence(timeout: 20))
        app.buttons["chat.actions"].tap()
        let compact = app.buttons["chat.session.compact"]
        XCTAssertTrue(compact.waitForExistence(timeout: 8)); XCTAssertTrue(compact.isEnabled)
        compact.tap(); XCTAssertFalse(compact.isEnabled)
        XCTAssertTrue(app.buttons["chat.session.model"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Session controls and context checkpoint"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["chat.session.fork"].tap()
        let identity = app.buttons["chat.session"]
        XCTAssertTrue(identity.waitForExistence(timeout: 8))
        XCTAssertTrue(identity.label.contains("(fork)"))
        XCTAssertFalse(app.buttons["chat.composer.stop"].exists)
    }

    @MainActor func testSessionControlsRemainReachableWithLargeTextAndRTL() {
        let app = launch(["--large-text-fixtures", "--rtl-fixtures", "--reduced-motion-fixtures"])
        let actions = app.buttons["chat.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20)); actions.tap()
        XCTAssertTrue(app.buttons["chat.session.done"].waitForExistence(timeout: 8))
        let pin = app.buttons["chat.session.pin"]
        XCTAssertTrue(pin.exists); XCTAssertGreaterThanOrEqual(pin.frame.height, 100)
        XCTAssertGreaterThan(pin.frame.minX, app.buttons["chat.session.unread"].frame.minX, "RTL must mirror the action order")
        let model = app.buttons["chat.session.model"]
        for _ in 0..<4 where !model.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(model.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Session sheet large text and RTL"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["chat.session.done"].tap()
        XCTAssertTrue(app.textFields["chat.composer.text"].exists)
    }

    @MainActor func testDraftingDuringStreamingDoesNotCancelTheActiveReply() {
        let app = launch(["--rapid-stream-fixtures"])
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20)); composer.tap(); composer.typeText("Stream the review")
        app.buttons["chat.composer.send"].tap()
        let stop = app.buttons["chat.composer.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        composer.tap(); composer.typeText("Next draft")
        expectDraft("Next draft", in: composer)
        XCTAssertTrue(stop.exists, "Editing a draft must not silently stop the active request")
        stop.tap()
        let stopped = NSPredicate { _, _ in !stop.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stopped, object: nil)], timeout: 10), .completed)
        XCTAssertEqual(composer.value as? String, "Next draft")
    }
}
