import XCTest

final class LocalizationFlows: XCTestCase {
    @MainActor func testHindi() { verify("hi", region:"IN", next:"जारी रखें", message:"संदेश", repositories:"रिपॉज़िटरी", approve:"डिप्लॉयमेंट मंज़ूर करें") }
    @MainActor func testGerman() { verify("de", region:"DE", next:"Weiter", message:"Nachricht", repositories:"Repositories", approve:"Deployment genehmigen") }
    @MainActor func testSpanish() { verify("es", region:"ES", next:"Continuar", message:"Mensaje", repositories:"Repositorios", approve:"Aprobar despliegue") }
    @MainActor func testArabic() { verify("ar", region:"SA", next:"متابعة", message:"رسالة", repositories:"المستودعات", approve:"الموافقة على النشر") }
    @MainActor func testTurkish() { verify("tr", region:"TR", next:"Devam", message:"Mesaj", repositories:"Depolar", approve:"Dağıtımı onayla") }
    @MainActor func testJapanese() { verify("ja", region:"JP", next:"続ける", message:"メッセージ", repositories:"リポジトリ", approve:"デプロイを承認") }

    @MainActor private func verify(_ language:String,region:String,next:String,message:String,repositories:String,approve:String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures","--onboarding-fixtures","--reduced-motion-fixtures","--workspace","chat",
                               "-AppleLanguages","(\(language))","-AppleLocale","\(language)_\(region)"]
        app.launch()
        let advance = app.buttons["onboarding.continue"]
        XCTAssertTrue(advance.waitForExistence(timeout:25))
        XCTAssertEqual(advance.label,next)
        capture(app,"\(language) onboarding")
        advance.tap(); advance.tap(); advance.tap()

        let compose = app.buttons["navigation.newChat"]
        XCTAssertTrue(compose.waitForExistence(timeout:15))
        compose.tap()

        let composer = app.textFields["chat.composer.text"]
        XCTAssertTrue(composer.waitForExistence(timeout:15))
        XCTAssertEqual(composer.label,message)
        let sidebar = app.workspaceNavigationControl,newChat = app.buttons["navigation.newChat"]
        if language == "ar" { XCTAssertGreaterThan(sidebar.frame.minX,newChat.frame.maxX) }
        else { XCTAssertLessThan(sidebar.frame.maxX,newChat.frame.minX) }
        capture(app,"\(language) chat")

        app.openWorkspaceNavigation()
        let repository = app.buttons["navigation.repositories"]
        XCTAssertTrue(repository.waitForExistence(timeout:8))
        XCTAssertTrue(repository.label.contains(repositories))
        app.revealWorkspace("tools")
        app.buttons["navigation.tools"].tap()
        let group = app.buttons["tools.group.Actions"]
        XCTAssertTrue(group.waitForExistence(timeout:10))
        group.tap()
        let deployment = app.buttons["tool.approve_deployment"]
        XCTAssertTrue(deployment.waitForExistence(timeout:8))
        XCTAssertTrue(deployment.label.contains(approve))
        capture(app,"\(language) tool catalog")
        app.terminate()
    }

    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let attachment = XCTAttachment(screenshot:app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
