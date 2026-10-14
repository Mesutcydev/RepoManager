import XCTest

final class RepoManagerFlows: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
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
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20)); navigate(app,to:"repositories")
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
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20)); navigate(app,to:"repositories")
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
        app.buttons["navigation.sidebar"].tap()
        XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout:5))
    }
    @MainActor func testRTLSettingsPhysicalTouch() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--large-text-fixtures","--rtl-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20))
        app.buttons["navigation.sidebar"].tap()
        let settings = app.buttons["navigation.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:5))
        let bounds = settings.frame
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:bounds.midX,dy:bounds.midY)).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5),"Touching the visible Settings control opens its native sheet")
    }
    @MainActor func testLargeTextRTLAndSidebarAccess() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--large-text-fixtures","--rtl-fixtures"]; app.launch()
        let sidebar = app.buttons["navigation.sidebar"]
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
        XCTAssertGreaterThan(drawer.frame.minX,app.frame.minX,"A closed drawer must not leak in from the opposite edge")
        let open = XCTAttachment(screenshot:app.screenshot()); open.name = "Large text RTL leading drawer"; open.lifetime = .keepAlways; add(open)
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
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20)); navigate(app,to:"repositories")
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
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20)); navigate(app,to:"pullRequests")
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
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20))
        app.buttons["navigation.sidebar"].tap()
        XCTAssertFalse(app.buttons["navigation.models"].exists); XCTAssertFalse(app.buttons["navigation.lens"].exists)
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
            XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20))
            XCTAssertGreaterThanOrEqual(app.buttons["navigation.sidebar"].frame.height,44)
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
            app.buttons["navigation.sidebar"].tap(); app.buttons["navigation.settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
            let settings = XCTAttachment(screenshot:app.screenshot()); settings.name = "UX-\(appearance)-settings"; settings.lifetime = .keepAlways; add(settings)
            app.terminate()
        }
    }
    @MainActor func testToolArgumentsCannotUseStaleInvalidJSON() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-fixtures","--repository-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["navigation.sidebar"].waitForExistence(timeout:20)); navigate(app,to:"tools")
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
        let sidebar = app.buttons["navigation.sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout:5),file:file,line:line); sidebar.tap()
        let drawer = app.otherElements["navigation.drawer"]
        XCTAssertTrue(drawer.waitForExistence(timeout:5),file:file,line:line)
        let settled = NSPredicate { _,_ in
            drawer.exists && drawer.frame.minX >= app.frame.minX-1 && drawer.frame.maxX <= app.frame.maxX+1
        }
        XCTAssertTrue(XCTWaiter.wait(for:[expectation(for:settled,evaluatedWith:drawer)],timeout:5) == .completed,file:file,line:line)
        let target = app.buttons["navigation.\(destination)"]
        XCTAssertTrue(target.waitForExistence(timeout:5),file:file,line:line)
        let scroll = app.scrollViews["navigation.drawerScroll"]
        for _ in 0..<3 where target.frame.maxY > scroll.frame.maxY || target.frame.minY < scroll.frame.minY { scroll.swipeUp() }
        let bounds = target.frame
        XCTAssertGreaterThanOrEqual(bounds.minY,scroll.frame.minY,file:file,line:line)
        XCTAssertLessThanOrEqual(bounds.maxY,scroll.frame.maxY,file:file,line:line)
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:bounds.midX,dy:bounds.midY)).tap()
        let closed = NSPredicate { _,_ in !drawer.exists }
        let result = XCTWaiter.wait(for:[expectation(for:closed,evaluatedWith:drawer)],timeout:5)
        if result != .completed {
            let snapshot = XCTAttachment(screenshot:app.screenshot()); snapshot.name = "Navigation did not close — \(destination)"; snapshot.lifetime = .keepAlways; add(snapshot)
            let tree = XCTAttachment(string:app.debugDescription); tree.name = "Synthetic navigation accessibility hierarchy"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(result == .completed,"Selecting a workspace closes the drawer",file:file,line:line)
    }

}
