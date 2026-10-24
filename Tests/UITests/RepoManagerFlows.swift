import XCTest
import UIKit

final class RepoManagerFlows: XCTestCase {
    @MainActor func testBackgroundedAuditRetainsProgressAndContinueKeepsTheTask() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures", "--background-resume-fixtures", "--workspace", "chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20)); composer.tap(); composer.typeText("Audit repo for cleanup and better display")
        app.buttons["chat.composer.send"].tap()
        let pending = app.buttons["chat.tool.background_map"], completed = app.buttons["chat.tool.background_files"]
        XCTAssertTrue(pending.waitForExistence(timeout: 15)); XCTAssertEqual(pending.value as? String, "running")
        XCTAssertEqual(completed.value as? String, "success")
        XCUIDevice.shared.press(.home)
        let backgrounded = NSPredicate { _, _ in app.state == .runningBackground || app.state == .runningBackgroundSuspended }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: backgrounded, object: nil)], timeout: 10), .completed)
        app.activate()
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        XCTAssertTrue(pending.waitForExistence(timeout: 10)); XCTAssertEqual(pending.value as? String, "cancelled")
        XCTAssertEqual(completed.value as? String, "success")
        XCTAssertFalse(app.buttons["chat.composer.stop"].exists)
        app.buttons["More response actions"].firstMatch.tap()
        app.buttons["chat.response.continue"].tap()
        XCTAssertTrue(app.staticTexts["Background audit resumed"].waitForExistence(timeout: 30), "Continue must retain the task, paired prior results, and complete another read")
        XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chat.tool.resumed_read"].value as? String, "success")
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Audit continues with retained progress after backgrounding"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testRepositoryAuditContinuesBeyondTwentyFiveCalls() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures", "--extended-audit-fixtures", "--workspace", "chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20)); composer.tap(); composer.typeText("Audit repo for cleanup and better display")
        app.buttons["chat.composer.send"].tap()
        XCTAssertTrue(app.staticTexts["Extended repository audit complete"].waitForExistence(timeout: 45))
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout: 5))
        let calls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.tool.extended_read_"))
        XCTAssertEqual(calls.count, 35)
        XCTAssertTrue(calls.allElementsBoundByIndex.allSatisfy { ($0.value as? String) == "success" })
    }
    @MainActor func testRepositoryAuditDoesNotStopAtPreambleOrBlankProceed() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--completed-response-fixtures","--workspace","chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:20))
        XCTAssertTrue(app.buttons["Plan"].exists); app.buttons["Plan"].tap()
        for prompt in ["Audit repo for cleanup and better display","Proceed"] {
            let replies = app.staticTexts.matching(identifier:"Repository audit complete")
            let before = replies.count
            composer.tap(); composer.typeText(prompt); app.buttons["chat.composer.send"].tap()
            let completed = NSPredicate { _,_ in replies.count == before+1 }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:completed,object:nil)],timeout:25),.completed,"The audit must read the repository and produce findings without another Proceed")
            XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout:10))
            XCTAssertFalse(app.alerts["Repo Manager"].exists)
            let calls = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","chat.tool.call_read_"))
            XCTAssertGreaterThan(calls.count,0)
            XCTAssertEqual(calls.element(boundBy:calls.count-1).value as? String,"success")
        }
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Audit and Proceed both execute repository tools and finish"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testEmptyResponseExplainsFailureAndRestoresDraft() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--empty-response-fixtures","--workspace","chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:20)); composer.tap(); composer.typeText("Proceed"); app.buttons["chat.composer.send"].tap()
        let notice = app.staticTexts["No reply received"]
        XCTAssertTrue(notice.waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["chat.composer.send"].waitForExistence(timeout:5)); XCTAssertTrue(app.buttons["chat.composer.send"].isEnabled)
        XCTAssertFalse(app.buttons["chat.composer.stop"].exists); XCTAssertEqual(composer.value as? String,"Proceed")
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Empty response has a visible explanation and retained draft"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testRapidLongResponseKeepsReadingPositionAndChatControls() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--rapid-stream-fixtures","--workspace","chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:20)); composer.tap(); composer.typeText("Stream the repository audit")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        let referenceImage = app.screenshot().image
        let frames = [app.workspaceNavigationControl,app.buttons["chat.modelPicker"],app.buttons["navigation.newChat"],app.buttons["chat.repositoryContext"]].map { "\($0.identifier): \($0.frame)" }.joined(separator:"\n")
        let frameData = XCTAttachment(string:frames); frameData.name = "Fixed chrome reference frames"; frameData.lifetime = .keepAlways; add(frameData)
        let chrome = try [app.workspaceNavigationControl,app.buttons["chat.modelPicker"],app.buttons["navigation.newChat"],app.buttons["chat.repositoryContext"]].map { element in
            let frame = element.frame
            return (frame,try brightPixels(referenceImage,frame:frame,screen:app.frame))
        }
        let referenceShot = XCTAttachment(image:referenceImage); referenceShot.name = "Chat chrome before streaming"; referenceShot.lifetime = .keepAlways; add(referenceShot)
        app.buttons["chat.composer.send"].tap()
        let keyboardHidden = NSPredicate { _,_ in !app.keyboards.firstMatch.exists }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:keyboardHidden,object:nil)],timeout:5),.completed)
        let composerY = composer.frame.minY, toolbarY = app.buttons["chat.modelPicker"].frame.minY
        XCTAssertTrue(app.staticTexts["Streaming audit"].waitForExistence(timeout:8))
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        let viewport = transcript.frame
        let liveText = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Section "))
        XCTAssertTrue(liveText.firstMatch.waitForExistence(timeout:5))
        for _ in 0..<3 {
            XCTAssertTrue(liveText.allElementsBoundByIndex.contains { $0.frame.intersects(viewport) }, "The followed transcript has visible reply content")
            try assertChrome(app,reference:chrome)
            let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Followed streaming content stays visible"; shot.lifetime = .keepAlways; add(shot)
            RunLoop.current.run(until:Date().addingTimeInterval(0.3))
        }
        let older = app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","I can inspect files, compare changes")).firstMatch
        // On iPad the earlier message can still fit while following the footer.
        // Always perform the reader's gesture before asserting paused following.
        transcript.swipeDown()
        for _ in 0..<6 { if older.frame.intersects(viewport) { break }; transcript.swipeDown() }
        XCTAssertTrue(older.frame.intersects(viewport), "The reader can return to earlier content while the answer streams")
        var previousY = CGFloat.nan,stableSamples = 0
        let readingSettled = NSPredicate { _,_ in
            let y = older.frame.minY
            stableSamples = abs(y-previousY)<0.5 ? stableSamples+1 : 0
            previousY = y
            return stableSamples>=2
        }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:readingSettled,object:nil)],timeout:5),.completed,"Wait for the reader's swipe to settle before measuring streaming movement")
        let readingY = older.frame.minY
        for index in 0..<10 {
            XCTAssertTrue(older.frame.intersects(viewport), "Earlier content vanished at sample \(index)")
            try assertChrome(app,reference:chrome)
            XCTAssertEqual(older.frame.minY,readingY,accuracy:4, "Streaming moved the reader away from the chosen message")
            XCTAssertEqual(composer.frame.minY,composerY,accuracy:2)
            XCTAssertEqual(app.buttons["chat.modelPicker"].frame.minY,toolbarY,accuracy:2)
            XCTAssertFalse(app.alerts["Repo Manager"].exists)
            if index == 0 || index == 9 { let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Rapid streaming reading position \(index)"; shot.lifetime = .keepAlways; add(shot) }
            RunLoop.current.run(until:Date().addingTimeInterval(0.4))
        }
        XCTAssertTrue(app.buttons["chat.latest"].exists); app.buttons["chat.latest"].tap()
        XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout:25))
        XCTAssertTrue(app.staticTexts["Audit complete"].frame.intersects(viewport))
        try assertChrome(app,reference:chrome)
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Rapid completed reply remains on screen"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor private func assertChrome(_ app:XCUIApplication,reference:[(CGRect,[Bool])]) throws {
        let current = app.screenshot().image
        for (frame,expected) in reference {
            let actual = try brightPixels(current,frame:frame,screen:app.frame)
            let count = expected.filter { $0 }.count
            XCTAssertGreaterThan(count,20,"The reference must contain visible chrome")
            XCTAssertEqual(actual.count,expected.count)
            guard count > 0,actual.count == expected.count else { continue }
            let retained = expected.indices.filter { expected[$0] && actual[$0] }.count
            XCTAssertGreaterThan(Double(retained)/Double(count),0.65,"Transcript content covered a fixed chat control")
        }
    }
    private func brightPixels(_ image:UIImage,frame:CGRect,screen:CGRect) throws -> [Bool] {
        let source = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(source.width)/screen.width
        let rect = CGRect(x:(frame.minX-screen.minX)*scale,y:(frame.minY-screen.minY)*scale,width:frame.width*scale,height:frame.height*scale).integral
        let crop = try XCTUnwrap(source.cropping(to:rect))
        let width = crop.width,height = crop.height
        var pixels = [UInt8](repeating:0,count:width*height*4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop,in:CGRect(x:0,y:0,width:width,height:height))
        }
        return (0..<(width*height)).map { pixels[$0*4]>160 && pixels[$0*4+1]>160 && pixels[$0*4+2]>160 }
    }

    @MainActor func testRepositoryBranchFailureStaysWithPicker() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--branch-request-error-fixtures","--workspace","chat"]; app.launch()
        XCTAssertTrue(app.buttons["chat.repositoryContext"].waitForExistence(timeout:20)); app.buttons["chat.repositoryContext"].tap()
        let repo = app.buttons["repository.pick.42"]
        XCTAssertTrue(repo.waitForExistence(timeout:15)); repo.tap()
        let notice = app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Branches could not load")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout:10))
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        XCTAssertTrue(app.buttons["Use this repository and branch"].isEnabled)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Branch failure stays in repository picker"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.textFields["chat.composer.text"].isHittable)
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
    }

    @MainActor func testBackgroundSyncFailureDoesNotInterruptCompletedResponse() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--background-sync-error-fixtures","--workspace","chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:20)); composer.tap(); composer.typeText("Hello")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        app.buttons["chat.composer.send"].tap()
        XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout:20))
        let actions = app.buttons.matching(NSPredicate(format:"label == %@","More response actions"))
        XCTAssertGreaterThan(actions.count,0); actions.element(boundBy:actions.count-1).tap(); app.buttons["Response details"].tap()
        XCTAssertTrue(app.staticTexts["Response details"].waitForExistence(timeout:5))
        XCTAssertFalse(app.alerts["Repo Manager"].waitForExistence(timeout:9), "An automatic sync failure must not become a reply failure modal")
        XCTAssertTrue(app.staticTexts["Response details"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Response details survive failed background sync"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
    }

    @MainActor func testReplyAndReasoningRemainVisibleAcrossToolRounds() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures", "--reply-stability-fixtures", "--workspace", "chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20)); composer.tap(); composer.typeText("Audit with visible reasoning and retain earlier findings")
        app.buttons["chat.composer.send"].tap()
        let reasoning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "First reasoning summary remains visible.")).firstMatch
        let first = XCTAttachment(screenshot: app.screenshot()); first.name = "Reasoning begins"; first.lifetime = .keepAlways; add(first)
        XCTAssertTrue(reasoning.waitForExistence(timeout: 5), "Provider-returned reasoning is visible while the turn is active")
        let heading = app.staticTexts["Stable reply"]
        XCTAssertTrue(heading.waitForExistence(timeout: 8), "The reply keeps the same Markdown presentation while streaming")
        let firstTool = app.buttons["chat.tool.fixture-read-0"]
        XCTAssertTrue(firstTool.waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["chat.composer.stop"].exists)
        XCTAssertTrue(heading.exists); XCTAssertTrue(reasoning.exists)
        let toolFrame = firstTool.frame
        let during = XCTAttachment(screenshot: app.screenshot()); during.name = "Reply and reasoning during tool execution"; during.lifetime = .keepAlways; add(during)
        let success = NSPredicate { _, _ in firstTool.value as? String == "success" }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: success, evaluatedWith: firstTool)], timeout: 10), .completed)
        XCTAssertEqual(firstTool.frame.width, toolFrame.width, accuracy: 0.5)
        XCTAssertEqual(firstTool.frame.height, toolFrame.height, accuracy: 0.5)
        XCTAssertTrue(heading.exists); XCTAssertTrue(reasoning.exists)
        let secondTool = app.buttons["chat.tool.fixture-read-1"]
        XCTAssertTrue(secondTool.waitForExistence(timeout: 12)); XCTAssertTrue(app.buttons["chat.composer.stop"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "The initial findings stay visible throughout the audit.")).firstMatch.exists)
        let second = XCTAttachment(screenshot: app.screenshot()); second.name = "Earlier reply retained during second tool round"; second.lifetime = .keepAlways; add(second)
        XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["The audit is complete."].exists)
        let disclosure = app.buttons["chat.reasoning"]
        XCTAssertTrue(disclosure.exists); disclosure.tap()
        XCTAssertTrue(reasoning.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Second reasoning summary is retained across the tool round.")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Final reasoning summary is retained after completion.")).firstMatch.exists)
        let final = XCTAttachment(screenshot: app.screenshot()); final.name = "Completed reply with retained reasoning expanded"; final.lifetime = .keepAlways; add(final)
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
    }

    @MainActor func testRepositoryAuditContinuesAfterLargeToolResults() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures", "--context-budget-fixtures", "--workspace", "chat"]; app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20)); composer.tap(); composer.typeText("Audit repo for cleanup and better display")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        app.buttons["chat.composer.send"].tap()
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Repository audit completed with partial tool coverage")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "Large successful tool results must allow the next model round")
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "parts of long tool results were omitted")).firstMatch.exists)
        XCTAssertTrue(app.buttons["chat.composer.voice"].waitForExistence(timeout: 5), "The composer is ready for another request")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Repository audit completes after large tool results"; shot.lifetime = .keepAlways; add(shot)
        composer.tap(); composer.typeText("Audit repo for cleanup and better display")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        app.buttons["chat.composer.send"].tap()
        let replies = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Repository audit completed with partial tool coverage"))
        let both = NSPredicate { _, _ in replies.count == 2 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: both, object: nil)], timeout: 30), .completed,
                       "A repeated audit must restore a valid tool/response history")
        XCTAssertFalse(app.alerts["Repo Manager"].exists)
        let repeated = XCTAttachment(screenshot: app.screenshot()); repeated.name = "Repeated repository audit retains both completed replies"; repeated.lifetime = .keepAlways; add(repeated)
    }

    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testChatGPTRequestFailurePreservesDraftAndSafeDiagnostics() throws {
        for editingNextDraft in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-fixtures", "--context-budget-fixtures", "--chatgpt-request-error-fixtures", "--workspace", "chat"]; app.launch()
            let composer = app.textFields["chat.composer.text"], prompt = "Audit repo for cleanup and better display"
            XCTAssertTrue(composer.waitForExistence(timeout: 20)); composer.tap(); composer.typeText(prompt)
            if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
            app.buttons["chat.composer.send"].tap()
            let next = "My next request"
            if editingNextDraft {
                XCTAssertTrue(app.staticTexts["list_files"].firstMatch.waitForExistence(timeout: 15))
                composer.tap(); composer.typeText(next)
            }
            let alert = app.alerts["Repo Manager"]
            XCTAssertTrue(alert.waitForExistence(timeout: 30))
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "HTTP 400")).firstMatch.exists)
            XCTAssertFalse(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "synthetic-secret")).firstMatch.exists)
            alert.buttons["OK"].tap()
            XCTAssertEqual(composer.value as? String, editingNextDraft ? next : prompt)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = editingNextDraft ? "New draft survives provider failure" : "Failed request restored to composer"; shot.lifetime = .keepAlways; add(shot)
        }
    }
    @MainActor func testProIncludesChatGPTAndUnlocksAPIProviders() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--pro-fixtures","--workspace","providers"]; app.launch()
        XCTAssertTrue(app.buttons["Add provider"].waitForExistence(timeout:20)); app.buttons["Add provider"].tap()
        app.buttons["provider.chatgpt"].tap()
        XCTAssertTrue(app.buttons["chatgpt.continue"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["pro.purchase"].exists)
        app.buttons["chatgpt.done"].tap()
        app.buttons["provider.preset.apple"].tap()
        XCTAssertTrue(app.navigationBars["Apple Intelligence"].waitForExistence(timeout:5))
        app.buttons["Cancel"].tap()
        app.buttons["provider.preset.openAI"].tap()
        XCTAssertTrue(app.buttons["pro.purchase"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["pro.price"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["pro.chatgptIncluded"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","API providers")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Custom HTTPS endpoints")).firstMatch.exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Pro one-time API-provider unlock"; shot.lifetime = .keepAlways; add(shot)
        let restore = app.buttons["pro.restore"]
        for _ in 0..<4 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable); restore.tap()
        XCTAssertTrue(app.staticTexts["No Pro purchase was found."].waitForExistence(timeout:5))
        app.buttons["pro.purchase"].tap()
        XCTAssertTrue(app.staticTexts["pro.unlocked"].waitForExistence(timeout:5))
        app.buttons["pro.continue"].tap()
        XCTAssertTrue(app.secureTextFields["API credential (Keychain only)"].waitForExistence(timeout:5))
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        app.buttons["pro.manage"].tap()
        app.buttons["pro.restore"].tap()
        XCTAssertTrue(app.staticTexts["Pro purchase restored."].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["pro.unlocked"].exists)
    }
    @MainActor func testPremiumPaywallRemainsReachableAtLargeTextInRTL() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures","--pro-fixtures","--workspace","providers","--large-text-fixtures","--rtl-fixtures","--reduced-motion-fixtures"]
        app.launch()
        let manage = app.buttons["pro.manage"]
        XCTAssertTrue(manage.waitForExistence(timeout:20)); manage.tap()
        XCTAssertTrue(app.staticTexts["pro.chatgptIncluded"].waitForExistence(timeout:5))
        let restore = app.buttons["pro.restore"]
        for _ in 0..<12 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable); restore.tap()
        XCTAssertTrue(app.staticTexts["pro.message"].waitForExistence(timeout:5))
        let purchase = app.buttons["pro.purchase"]
        for _ in 0..<4 where !purchase.isHittable { app.swipeDown() }
        XCTAssertTrue(purchase.isHittable); purchase.tap()
        XCTAssertTrue(app.staticTexts["pro.unlocked"].waitForExistence(timeout:5))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Premium paywall accessibility RTL"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["pro.done"].tap()
        XCTAssertTrue(app.buttons["pro.manage"].waitForExistence(timeout:5))
    }
    @MainActor func testChatGPTSignInRequiresDisclosureAndNoAPIKey() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--workspace","providers"]; app.launch()
        XCTAssertTrue(app.buttons["Add provider"].waitForExistence(timeout:20)); app.buttons["Add provider"].tap()
        XCTAssertTrue(app.buttons["provider.chatgpt"].waitForExistence(timeout:5)); app.buttons["provider.chatgpt"].tap()
        let signIn = app.buttons["chatgpt.continue"]
        XCTAssertTrue(signIn.waitForExistence(timeout:5)); XCTAssertFalse(signIn.isEnabled)
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        XCTAssertFalse(app.textFields["HTTPS endpoint"].exists)
        let disclosure = app.switches["chatgpt.disclosure"]
        XCTAssertTrue(disclosure.exists)
        // SwiftUI exposes the label and UISwitch as a composite AX switch.
        // Tap the trailing control rather than the label's centre.
        disclosure.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(disclosure.value as? String,"1")
        let enabled = NSPredicate { _,_ in signIn.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:enabled,evaluatedWith:signIn)],timeout:5),.completed)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "ChatGPT native sign-in and disclosure"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["chatgpt.done"].tap()
        XCTAssertTrue(app.buttons["provider.chatgpt"].waitForExistence(timeout:5))
    }
    @MainActor func testChatGPTSafariReturnRetainsAuthorizationAndCanCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures","--chatgpt-pairing-fixtures","--workspace","providers"]; app.launch()
        XCTAssertTrue(app.buttons["Add provider"].waitForExistence(timeout:20)); app.buttons["Add provider"].tap()
        XCTAssertTrue(app.buttons["provider.chatgpt"].waitForExistence(timeout:5)); app.buttons["provider.chatgpt"].tap()
        let disclosure = app.switches["chatgpt.disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout:5))
        disclosure.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        let continueButton = app.buttons["chatgpt.continue"]
        for _ in 0..<3 where !continueButton.isHittable { app.swipeUp() }
        XCTAssertTrue(continueButton.isEnabled); continueButton.tap()
        let safari = XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
        let foreground = NSPredicate { _,_ in safari.state == .runningForeground && app.state != .runningForeground }
        XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:foreground,evaluatedWith:safari)],timeout:15),.completed)
        app.activate()
        let pending = app.staticTexts["chatgpt.pending"]
        XCTAssertTrue(pending.waitForExistence(timeout:20),"The original OAuth attempt survives background workspace locking")
        let reopen = app.buttons["chatgpt.openSafari"]
        for _ in 0..<3 where !reopen.isHittable { app.swipeUp() }
        XCTAssertTrue(reopen.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Close"].exists,"No embedded browser is presented")
        XCTAssertFalse(app.otherElements["privacy.sheet-cover"].exists)
        XCTAssertFalse(app.otherElements["privacy.cover"].exists)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "ChatGPT Safari return retains authorization"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["chatgpt.cancelAttempt"].tap()
        XCTAssertFalse(pending.exists); XCTAssertTrue(continueButton.isEnabled)
        app.buttons["chatgpt.done"].tap()
    }

    @MainActor func testDictationAuthorizationDoesNotCrash() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--workspace","voice"]; app.launch()
        let start = app.buttons["Start dictation"]
        XCTAssertTrue(start.waitForExistence(timeout:20)); start.tap()
        let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        // Exercise actual TCC callbacks; grant only this QA app's requested
        // microphone and speech permissions. Audio is never retained by tests.
        for _ in 0..<3 {
            guard springboard.alerts.firstMatch.waitForExistence(timeout:5) else { break }
            let alert = springboard.alerts.firstMatch
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() }
            else if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
            else { XCTFail("Unexpected dictation permission prompt"); return }
        }
        let unavailable = app.alerts["Repo Manager"].staticTexts["This capability is unavailable for this account or device."]
        let running = NSPredicate { _,_ in
            app.state == .runningForeground && (app.buttons["Stop voice"].exists || unavailable.exists)
        }
        XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:running,evaluatedWith:app)],timeout:20),.completed,"Speech permission completion leaves the app running")
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Dictation after speech permission"; shot.lifetime = .keepAlways; add(shot)
        if app.buttons["Stop voice"].exists { app.buttons["Stop voice"].tap() }
        else { app.alerts["Repo Manager"].buttons["OK"].tap() }
        XCTAssertTrue(start.exists)
    }

    @MainActor func testGitHubPairingUsesBundledIdentityAndCanCancel() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--github-pairing-fixtures"]; app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20)); navigate(app,to:"repositories")
        app.buttons["Pair GitHub"].tap()
        XCTAssertTrue(app.buttons["github.connect"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["github.connect"].isEnabled)
        XCTAssertFalse(app.textFields["Dedicated GitHub App client ID"].exists)
        XCTAssertFalse(app.secureTextFields["github.token"].exists)
        app.buttons["github.connect"].tap()
        XCTAssertTrue(app.staticTexts["github.userCode"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["github.authorize"].exists)
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "GitHub device authorization"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["github.cancelAttempt"].tap()
        XCTAssertTrue(app.buttons["github.connect"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["github.userCode"].exists)
        app.buttons["github.advanced"].tap()
        XCTAssertTrue(app.secureTextFields["github.token"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["github.connectToken"].isEnabled)
        app.buttons["github.cancel"].tap()
        XCTAssertTrue(app.buttons["Pair GitHub"].waitForExistence(timeout:5))
    }
    @MainActor func testGitHubSafariReturnKeepsPendingAuthorization() throws {
        // External Safari handoff with a synthetic code. No credentials or grants.
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--github-pairing-fixtures"]; app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20)); navigate(app,to:"repositories")
        app.buttons["Pair GitHub"].tap()
        XCTAssertTrue(app.buttons["github.connect"].waitForExistence(timeout:5)); app.buttons["github.connect"].tap()
        let code = app.staticTexts["github.userCode"]
        XCTAssertTrue(code.waitForExistence(timeout:5)); XCTAssertEqual(code.label,"ABCD-EFGH")
        XCTAssertGreaterThanOrEqual(app.buttons["github.authorize"].frame.height,48)
        XCTAssertGreaterThanOrEqual(app.buttons["github.copyCode"].frame.height,44)
        app.buttons["github.authorize"].tap()
        let safari = XCUIApplication(bundleIdentifier:"com.apple.mobilesafari")
        let foreground = NSPredicate { _,_ in safari.state == .runningForeground && app.state != .runningForeground }
        XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:foreground,evaluatedWith:safari)],timeout:15),.completed,"Authorization opens the separate Safari app")
        app.activate()
        XCTAssertTrue(code.waitForExistence(timeout:20),"The original device code survives browser handoff and workspace restoration")
        XCTAssertEqual(code.label,"ABCD-EFGH")
        XCTAssertFalse(app.buttons["Close"].exists,"There is no embedded browser")
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Safari return retains GitHub sign-in"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["github.cancelAttempt"].tap()
        XCTAssertTrue(app.buttons["github.connect"].waitForExistence(timeout:5)); XCTAssertFalse(code.exists)
        app.buttons["github.cancel"].tap()
        app.openWorkspaceNavigation()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout:5))
    }
    @MainActor func testRTLSettingsPhysicalTouch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--large-text-fixtures","--rtl-fixtures"]; app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20))
        app.openWorkspaceNavigation()
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:5))
        let bounds = settings.frame
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:bounds.midX,dy:bounds.midY)).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5),"Touching the visible Settings control opens its native sheet")
    }
    @MainActor func testLargeTextRTLAndSidebarAccess() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--large-text-fixtures","--rtl-fixtures"]; app.launch()
        let sidebar = app.workspaceNavigationControl
        XCTAssertTrue(sidebar.waitForExistence(timeout:20)); XCTAssertGreaterThan(sidebar.frame.midX,app.frame.midX,"Leading navigation mirrors to the right")
        app.buttons["navigation.newChat"].tap()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:5)); XCTAssertGreaterThan(composer.frame.width,100)
        composer.tap(); composer.typeText("Keep my draft")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        XCTAssertTrue(app.buttons["Send message"].isHittable)
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Large text RTL chat"; shot.lifetime = .keepAlways; add(shot)
        sidebar.tap()
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["chat.modelPicker"].exists,"The modal drawer owns accessibility and touch focus")
        XCTAssertGreaterThanOrEqual(settings.frame.minX,app.frame.minX)
        XCTAssertLessThanOrEqual(settings.frame.maxX,app.frame.maxX)
        let drawer = app.otherElements["navigation.drawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout:5))
        XCTAssertEqual(drawer.frame.maxX,app.frame.maxX,accuracy:2,"The RTL drawer occupies the leading right edge")
        XCTAssertGreaterThanOrEqual(drawer.frame.minX,app.frame.minX,"The native sidebar stays inside the window")
        let open = XCTAttachment(screenshot:app.screenshot()); open.name = "Large text RTL leading drawer"; open.lifetime = .keepAlways; add(open)
        app.revealWorkspace("tools")
        let tools = app.buttons["navigation.tools"]
        let navigationScroll = app.scrollViews["navigation.drawerScroll"]
        XCTAssertTrue(navigationScroll.waitForExistence(timeout:5))
        for _ in 0..<6 {
            let viewport = navigationScroll.frame, target = tools.frame
            let delta:CGFloat
            if target.minY < viewport.minY { delta = min(viewport.height * 0.3,max(32,viewport.minY - target.minY + 8)) }
            else if target.maxY > viewport.maxY { delta = -min(viewport.height * 0.3,max(32,target.maxY - viewport.maxY + 8)) }
            else { break }
            let start = navigationScroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
            start.press(forDuration:0.2,thenDragTo:start.withOffset(CGVector(dx:0,dy:delta)))
        }
        XCTAssertTrue(tools.waitForExistence(timeout:5))
        XCTAssertGreaterThanOrEqual(tools.frame.minY,navigationScroll.frame.minY)
        XCTAssertLessThanOrEqual(tools.frame.maxY,navigationScroll.frame.maxY)
        let target = tools.frame
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:target.midX,dy:target.midY)).tap()
        XCTAssertTrue(app.staticTexts["Tools"].firstMatch.waitForExistence(timeout:5),"The visible Tools target opens the workspace")
        XCTAssertTrue(app.buttons["tools.group.Actions"].isHittable,"The first visible group stays reachable at large text sizes")
        XCTAssertFalse(app.buttons["chat.modelPicker"].exists)
    }
    @MainActor func testRepositoryBrowserAndPullRequestDetails() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--repository-fixtures"]; app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20)); navigate(app,to:"repositories")
        XCTAssertTrue(app.buttons["Browse files"].waitForExistence(timeout:5)); app.buttons["Browse files"].tap()
        let file = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","README.md")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout:5)); file.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout:5))
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(file.exists, "The repository tree stays available beside the iPad editor")
            XCTAssertTrue(app.textViews.firstMatch.frame.width > 400)
        }
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Repository file workspace"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20)); navigate(app,to:"pullRequests")
        let pull = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Give the repository a clearer introduction")).firstMatch
        XCTAssertTrue(pull.waitForExistence(timeout:10)); pull.tap()
        XCTAssertTrue(app.staticTexts["README.md"].waitForExistence(timeout:5) || app.buttons.matching(NSPredicate(format:"label CONTAINS %@","README.md")).firstMatch.exists)
        let pr = XCTAttachment(screenshot:app.screenshot()); pr.name = "PR files and review workspace"; pr.lifetime = .keepAlways; add(pr)
    }
    @MainActor func testAppleGoZenAndAdaptiveReasoningControls() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["navigation.newChat"].waitForExistence(timeout:20)); app.buttons["navigation.newChat"].tap()
        let reasoning = app.buttons["chat.composer.thinking"]
        XCTAssertTrue(reasoning.waitForExistence(timeout:5)); reasoning.tap()
        XCTAssertTrue(app.buttons["Deep"].waitForExistence(timeout:5)); app.buttons["Deep"].tap()
        navigate(app,to:"providers")
        let addProvider = app.buttons["Add provider"]; XCTAssertTrue(addProvider.waitForExistence(timeout:5)); addProvider.tap()
        let picker = XCTAttachment(screenshot:app.screenshot()); picker.name = "Provider picker after native touch"; picker.lifetime = .keepAlways; add(picker)
        XCTAssertTrue(app.buttons["provider.preset.apple"].waitForExistence(timeout:5))
        app.buttons["provider.preset.apple"].tap()
        XCTAssertTrue(app.staticTexts["Apple Intelligence"].waitForExistence(timeout:5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        XCTAssertTrue(app.switches["Allow Apple model requests"].exists)
        app.buttons["Cancel"].tap()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout:5) { search.tap(); search.typeText("OpenCode") }
        XCTAssertTrue(app.buttons["provider.preset.openCodeGo"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["provider.preset.openCodeZen"].exists)
    }
    @MainActor func testOnboardingReviewAndFinish() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--onboarding-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout:20))
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["Connect GitHub"].waitForExistence(timeout:5))
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.review"].waitForExistence(timeout:5)); app.buttons["onboarding.review"].tap()
        XCTAssertTrue(app.staticTexts["One file. One branch. Your review."].exists)
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.buttons["navigation.newChat"].waitForExistence(timeout:5))
    }

    @MainActor func testSidebarAndDraftRetention() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["navigation.newChat"].waitForExistence(timeout:20))
        app.buttons["navigation.newChat"].tap()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:5)); composer.tap(); composer.typeText("Review my pending repository work"); waitForValue(composer,"Review my pending repository work")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        navigate(app,to:"tools")
        XCTAssertTrue(app.buttons["tools.catalog"].waitForExistence(timeout:5))
        XCTAssertFalse(composer.isHittable)
        XCTAssertFalse(app.buttons["chat.modelPicker"].exists, "Hidden workspaces must not expose chat controls to VoiceOver")
        navigate(app,to:"chats")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "history.")).firstMatch.tap()
        XCTAssertTrue(composer.waitForExistence(timeout:5)); XCTAssertEqual(composer.value as? String,"Review my pending repository work")
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"chat.modelPicker").firstMatch.waitForExistence(timeout:5))
    }
    @MainActor func testProviderDisclosureAndNoLocalModels() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures"]; app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20))
        app.openWorkspaceNavigation()
        XCTAssertFalse(app.buttons["navigation.models"].exists); XCTAssertFalse(app.buttons["navigation.lens"].exists)
        app.revealWorkspace("providers")
        app.buttons["navigation.providers"].tap()
        XCTAssertTrue(app.buttons["Add provider"].waitForExistence(timeout:5)); app.buttons["Add provider"].tap()
        let preset = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "OpenAI")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout:5)); preset.tap()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
    }

    @MainActor func testReducedMotionLaunchAndStreamingStop() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--reduced-motion-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["navigation.newChat"].waitForExistence(timeout:20)); app.buttons["navigation.newChat"].tap()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:5)); composer.tap(); composer.typeText("Verify streaming and cancellation")
        app.buttons["Send message"].tap()
        let stop = app.buttons["Stop response"]
        XCTAssertTrue(stop.waitForExistence(timeout:5)); stop.tap()
        XCTAssertTrue(app.buttons["Voice conversation"].waitForExistence(timeout:5))
        composer.tap(); composer.typeText("Preserved after Stop"); waitForValue(composer,"Preserved after Stop")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        navigate(app,to:"repositories")
        XCTAssertTrue(app.staticTexts["Repositories"].firstMatch.waitForExistence(timeout:5)); XCTAssertFalse(composer.isHittable)
        navigate(app,to:"chats")
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "history.")).firstMatch.tap()
        XCTAssertTrue(composer.waitForExistence(timeout:5)); waitForValue(composer,"Preserved after Stop")
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Branded chat after cancellation"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testWorkspaceVisualAuditDarkAndLight() throws {
        let pages:[(String,String)] = [("chats","Chats"),("repositories","Repositories"),("providers","Providers"),("changes","Changes"),("issues","Issues"),("pullRequests","Pull requests"),("actions","Actions"),("releases","Releases"),("security","Security"),("activity","Activity"),("tools","Tools"),("voice","Voice"),("apiServer","API server")]
        for appearance in ["dark","light"] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--repository-fixtures"]
            if appearance == "light" { app.launchArguments.append("--light-appearance-fixtures") }
            app.launch()
            XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20))
            XCTAssertGreaterThan(app.workspaceNavigationControl.frame.height,0)
            for (destination,title) in pages {
                navigate(app,to:destination)
                XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout:10),"The \(title) workspace is visible")
                let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "UX-\(appearance)-\(destination)"; screenshot.lifetime = .keepAlways; add(screenshot)
                if destination == "repositories" {
                    // The repository fixture can already have a working scope.
                    // Its compact Change chip has the same 44-pt target contract.
                    let action = app.buttons["Select repository"].exists ? app.buttons["Select repository"] : app.buttons["Change"]
                    XCTAssertTrue(action.exists); XCTAssertGreaterThanOrEqual(action.frame.height,43.99)
                }
            }
            app.openWorkspaceNavigation(); app.buttons["navigation.settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
            let settings = XCTAttachment(screenshot:app.screenshot()); settings.name = "UX-\(appearance)-settings"; settings.lifetime = .keepAlways; add(settings)
            app.terminate()
        }
    }
    @MainActor func testToolArgumentsCannotUseStaleInvalidJSON() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--repository-fixtures"]; app.launch()
        XCTAssertTrue(app.workspaceNavigationControl.waitForExistence(timeout:20)); navigate(app,to:"tools")
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout:5)); search.tap(); search.typeText("calculator")
        let calculator = app.buttons["tool.calculator"]; XCTAssertTrue(calculator.waitForExistence(timeout:5)); calculator.tap()
        let advanced = app.switches["tool.advancedJSON"]; XCTAssertTrue(advanced.waitForExistence(timeout:5)); advanced.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(advanced.value as? String,"1")
        let json = app.descendants(matching:.any).matching(identifier:"tool.argumentsJSON").firstMatch
        if !json.exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(json.waitForExistence(timeout:5)); json.tap()
        json.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:80)+"{ invalid")
        XCTAssertFalse(app.buttons["Read selected scope"].isEnabled,"Invalid JSON must never execute earlier field values")
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Invalid tool JSON blocks execution"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func waitForValue(_ element:XCUIElement,_ text:String,file:StaticString = #filePath,line:UInt = #line) {
        let ready = NSPredicate { _,_ in element.exists && element.value as? String == text }
        XCTAssertTrue(XCTWaiter.wait(for:[expectation(for:ready,evaluatedWith:element)],timeout:5) == .completed,"The committed text must match exactly",file:file,line:line)
    }
    @MainActor private func navigate(_ app:XCUIApplication,to destination:String,file:StaticString = #filePath,line:UInt = #line) {
        let sidebar = app.workspaceNavigationControl
        XCTAssertTrue(sidebar.waitForExistence(timeout:5),file:file,line:line); app.openWorkspaceNavigation()
        let drawer = app.otherElements["navigation.drawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout:5),file:file,line:line)
        let settled = NSPredicate { _,_ in
            drawer.exists && drawer.frame.minX >= app.frame.minX-1 && drawer.frame.maxX <= app.frame.maxX+1
        }
        XCTAssertTrue(XCTWaiter.wait(for:[expectation(for:settled,evaluatedWith:drawer)],timeout:5) == .completed,file:file,line:line)
        app.revealWorkspace(destination)
        let target = app.buttons["navigation.\(destination)"]
        XCTAssertTrue(target.waitForExistence(timeout:5),file:file,line:line)
        let scroll = app.scrollViews["navigation.drawerScroll"]
        for _ in 0..<3 where target.frame.maxY > scroll.frame.maxY || target.frame.minY < scroll.frame.minY { scroll.swipeUp() }
        let bounds = target.frame
        XCTAssertGreaterThanOrEqual(bounds.minY,scroll.frame.minY,file:file,line:line)
        XCTAssertLessThanOrEqual(bounds.maxY,scroll.frame.maxY,file:file,line:line)
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:bounds.midX,dy:bounds.midY)).tap()
        let closed = NSPredicate { _,_ in !drawer.exists || sidebar.isHittable }
        let result = XCTWaiter.wait(for:[expectation(for:closed,evaluatedWith:drawer)],timeout:5)
        if result != .completed {
            let snapshot = XCTAttachment(screenshot:app.screenshot()); snapshot.name = "Navigation did not close — \(destination)"; snapshot.lifetime = .keepAlways; add(snapshot)
            let tree = XCTAttachment(string:app.debugDescription); tree.name = "Synthetic navigation accessibility hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(result == .completed,"Selecting a workspace exposes its detail while a wide sidebar can remain visible",file:file,line:line)
    }

}


/// Resize regressions use the same view and unsaved data throughout each test.
final class DuoLayoutFlows: XCTestCase {
    @MainActor func testChatDraftSurvivesResizingAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures","--repository-fixtures","--workspace","chat","--reduced-motion-fixtures"]
        app.launch()
        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:25))
        composer.tap(); composer.typeText("Keep this draft while the display changes")
        if app.buttons["keyboard.dismiss"].exists { app.buttons["keyboard.dismiss"].tap() }
        for orientation in [UIDeviceOrientation.landscapeLeft,.portrait,.landscapeRight,.portrait] {
            XCUIDevice.shared.orientation = orientation
            let retained = NSPredicate { _,_ in composer.exists && composer.value as? String == "Keep this draft while the display changes" }
            XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:retained,evaluatedWith:nil)],timeout:8),.completed)
            XCTAssertTrue(app.buttons["chat.composer.send"].isHittable)
            XCTAssertTrue(app.buttons["navigation.newChat"].isHittable)
            XCTAssertTrue(app.buttons["chat.modelPicker"].isHittable)
        }
        app.openWorkspaceNavigation()
        app.revealWorkspace("tools")
        XCTAssertTrue(app.buttons["navigation.tools"].waitForExistence(timeout:5))
        app.revealWorkspace("tools")
        let tools = app.buttons["navigation.tools"]
        let navigationScroll = app.scrollViews["navigation.drawerScroll"]
        for _ in 0..<6 where tools.frame.maxY > navigationScroll.frame.maxY || tools.frame.minY < navigationScroll.frame.minY { navigationScroll.swipeUp() }
        XCTAssertTrue(tools.isHittable); tools.tap()
        XCTAssertTrue(app.buttons["tools.group.Actions"].waitForExistence(timeout:5))
        app.openWorkspaceNavigation()
        let recent = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","navigation.recent.")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout:5)); recent.tap()
        XCTAssertTrue(composer.waitForExistence(timeout:5))
        XCTAssertEqual(composer.value as? String,"Keep this draft while the display changes")
    }
    @MainActor func testFileSelectionAndUnstagedEditSurviveResizing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures","--repository-fixtures","--workspace","repositories","--reduced-motion-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["Browse files"].waitForExistence(timeout:25)); app.buttons["Browse files"].tap()
        let file = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","README.md")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout:10)); file.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout:10))
        let loaded = NSPredicate { _,_ in editor.isEnabled && (editor.value as? String)?.contains("A thoughtful workspace") == true }
        XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:loaded,evaluatedWith:nil)],timeout:10),.completed)
        editor.tap(); editor.typeText("\nUnstaged resize regression draft.")
        for orientation in [UIDeviceOrientation.landscapeLeft,.portrait,.landscapeRight,.portrait] {
            XCUIDevice.shared.orientation = orientation
            let retained = NSPredicate { _,_ in (editor.value as? String)?.contains("Unstaged resize regression draft.") == true }
            XCTAssertEqual(XCTWaiter.wait(for:[expectation(for:retained,evaluatedWith:nil)],timeout:8),.completed)
            XCTAssertTrue(app.buttons["Stage edit"].exists)
        }
    }
}


/// Native split-view controls own navigation; secondary workspaces are disclosed explicitly.
extension XCUIApplication {
    @MainActor var workspaceNavigationControl: XCUIElement {
        let classic = buttons["navigation.sidebar"]
        if classic.exists { return classic }
        let back = descendants(matching:.any).matching(identifier:"BackButton").firstMatch
        if back.exists { return back }
        return buttons.matching(NSPredicate(format:"label IN %@",["Show Sidebar","Hide Sidebar"])).firstMatch
    }
    @MainActor func openWorkspaceNavigation() {
        let drawer = otherElements["navigation.drawer"]
        if !drawer.isHittable { workspaceNavigationControl.tap() }
    }
    @MainActor func revealWorkspace(_ destination:String) {
        let secondary = ["actions","releases","security","activity","providers","tools","voice","apiServer"]
        guard secondary.contains(destination) else { return }
        let target = buttons["navigation.\(destination)"]
        let scroll = scrollViews["navigation.drawerScroll"]
        if !target.exists, buttons["navigation.moreWorkspaces"].exists {
            let more = buttons["navigation.moreWorkspaces"]
            for _ in 0..<8 where !more.isHittable { scroll.swipeUp() }
            XCTAssertTrue(more.isHittable,"More workspaces remains reachable")
            more.tap()
        }
        for _ in 0..<12 where !target.isHittable { scroll.swipeUp() }
        XCTAssertTrue(target.isHittable,"The disclosed workspace remains reachable")
    }
}
