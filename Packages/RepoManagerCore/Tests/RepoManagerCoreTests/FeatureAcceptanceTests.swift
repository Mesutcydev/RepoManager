import Foundation
import Testing
import Sodium
@testable import RepoManagerCore

@Suite struct FeatureAcceptance {
    @Test func reportedUsageAccumulatesToolRoundsAndPreservesUnknowns() throws {
        var usage = RunUsage()
        #expect(try usage.update(Usage(input:20,output:1)) == Usage(input:20,output:1))
        #expect(try usage.update(Usage(output:7)) == Usage(input:20,output:7))
        #expect(usage.finishRound() == Usage(input:20,output:7))
        #expect(try usage.update(Usage(input:40,output:9,reasoning:3)) == Usage(input:60,output:16))
        #expect(usage.finishRound() == Usage(input:60,output:16))
        #expect(usage.finishRound() == Usage()) // A round without usage is unknown.
        #expect(throws:RMError.invalidInput) { try usage.update(Usage(output:-1)) }
        var model = ModelMetadata(id:"fixture"); model.inputCostPerMillion = 2; model.outputCostPerMillion = 8
        let pricing = try #require(MessagePricing(metadata:model))
        #expect(pricing.estimateUSD(Usage(input:1000,output:500)) == 0.006)
        #expect(pricing.estimateUSD(Usage(input:1000)) == nil)
        model.inputCostPerMillion = nil; #expect(MessagePricing(metadata:model) == nil)
        model.inputCostPerMillion = 2
        let gemini = try #require(MessagePricing(metadata:model,format:.gemini))
        #expect(gemini.estimateUSD(Usage(input:1000,output:500,reasoning:250)) == 0.008)
        #expect(gemini.estimateUSD(Usage(input:1000,output:500)) == nil)
    }
    struct Operation:Sendable {
        var name:String; var arguments:JSON; var suffix:String; var method:String
    }
    static let operations:[Operation] = [
        .init(name:"edit_issue",arguments:.object(["id":1,"body":.object(["state":"closed","title":"Reviewed issue"])]),suffix:"/issues/1",method:"PATCH"),
        .init(name:"inline_comment",arguments:.object(["id":1,"body":.object(["body":"Reviewed line","commit_id":.string(baseSHA),"path":"script.sh","line":1,"side":"RIGHT"])]),suffix:"/pulls/1/comments",method:"POST"),
        .init(name:"submit_review",arguments:.object(["id":1,"review_id":2,"body":.object(["event":"APPROVE"])]),suffix:"/pulls/1/reviews/2/events",method:"POST"),
        .init(name:"dispatch_workflow",arguments:.object(["id":1,"body":.object(["ref":"main","inputs":.object(["environment":"preview"])])]),suffix:"/actions/workflows/1/dispatches",method:"POST"),
        .init(name:"edit_release",arguments:.object(["id":1,"body":.object(["name":"Reviewed release","draft":false])]),suffix:"/releases/1",method:"PATCH"),
        .init(name:"set_collaborator",arguments:.object(["username":"colleague","body":.object(["permission":"pull"])]),suffix:"/collaborators/colleague",method:"PUT"),
        .init(name:"update_dependabot_alert",arguments:.object(["id":1,"body":.object(["state":"dismissed","dismissed_reason":"tolerable_risk","dismissed_comment":"Reviewed upstream advisory"])]),suffix:"/dependabot/alerts/1",method:"PATCH")
    ]
    @Test(arguments:operations) func reviewedManagementOperations(_ operation:Operation) async throws {
        let f = try await FixtureServices.make(); let chat = UUID(); await f.approvals.bind(chat,scope:f.scope)
        let definition = try ToolCatalog.named(operation.name)
        let plan = try await f.approvals.prepare(definition,arguments:operation.arguments,scope:f.scope,conversationID:chat)
        #expect(await f.fixture.writes().isEmpty)
        let receipt = try await f.approvals.confirm(plan.id)
        #expect(receipt.state == .completed)
        let write = try #require(await f.fixture.writes().last)
        #expect(write.url?.path.hasSuffix(operation.suffix) == true); #expect(write.httpMethod == operation.method)
        #expect(try JSON.parse(write.httpBody ?? Data()) == operation.arguments["body"])
        await #expect(throws:RMError.staleReview) { try await f.approvals.confirm(plan.id) }
        await f.fixture.setPermission(false)
        await #expect(throws:RMError.forbidden) { try await f.approvals.prepare(definition,arguments:operation.arguments,scope:f.scope,conversationID:chat) }
        #expect(await f.fixture.writes().count == 1)
    }
    @Test func secretsUseSealedBoxesAndOnlyNativeMetadata() async throws {
        let f = try await FixtureServices.make(); let keyPair = try #require(Sodium().box.keyPair())
        await f.fixture.setSecretPublicKey(Data(keyPair.publicKey).base64EncodedString())
        let canary = "RM-secret-value-canary-6e6b5e3f"
        let (operation,args) = try await f.github.secretPlanArguments(scope:f.scope,name:"DEPLOY_TOKEN",environment:nil,dependabot:false,value:Data(canary.utf8))
        #expect(!args.pretty.contains(canary))
        let encrypted = try #require(Data(base64Encoded:args["body"]["encrypted_value"].string ?? ""))
        let opened = try #require(Sodium().box.open(anonymousCipherText:Array(encrypted),recipientPublicKey:keyPair.publicKey,recipientSecretKey:keyPair.secretKey))
        #expect(Data(opened) == Data(canary.utf8))
        let id = UUID(); await f.approvals.bind(id,scope:f.scope)
        let context = ScopedToolContext(conversationID:id,repository:f.scope,mode:.act)
        #expect(!(await f.tools.available(context:context)).contains { $0.name == "set_secret" })
        let bypass = await f.tools.execute(ToolCall(name:"set_secret",arguments:args),context:context)
        #expect(bypass.status == .failure)
        let plan = try await f.approvals.prepare(ToolCatalog.named(operation),arguments:args,scope:f.scope,conversationID:id,native:true)
        #expect(plan.before["exists"].bool == false)
        let receipt = try await f.approvals.confirm(plan.id)
        #expect(!receipt.result.pretty.contains(canary)); #expect(receipt.reviewedArguments?["body"]["encrypted_value"] == JSON.null)
    }
    @Test func branchAndLabelParametersStaySingleURLSegments() async throws {
        let f = try await FixtureServices.make()
        let branchPath = try await f.github.expanded("repos/{owner}/{repo}/branches/{branch}/protection",arguments:.object(["branch":"feature/one"]),scope:f.scope)
        #expect(branchPath.hasSuffix("branches/feature%2Fone/protection"))
        let labelPath = try await f.github.expanded("repos/{owner}/{repo}/labels/{label}",arguments:.object(["label":"good first issue"]),scope:f.scope)
        #expect(labelPath.hasSuffix("labels/good%20first%20issue"))
        let url = try URLPolicy.append(URL(string:"https://api.github.com")!,segments:["branches","feature/one","protection"])
        #expect(URLComponents(url:url,resolvingAgainstBaseURL:false)?.percentEncodedPath == "/branches/feature%2Fone/protection")
    }
    @Test func modelPrivacyConsentIsCheckedBeforeRequests() throws {
        var profile = ProviderProfile(preset:.openCodeZen); profile.consentEndpoint = profile.endpoint
        let model = "muse-spark-1.3-contributor-free"
        #expect(throws:RMError.consentRequired) { try ProviderWire.request(RunRequest(conversationID:UUID(),profile:profile,model:model,messages:[ChatMessage(role:.user,text:"private context")]),key:"fixture") }
        profile.privacyConsentedModels = [model]
        #expect(try ProviderWire.request(RunRequest(conversationID:UUID(),profile:profile,model:model,messages:[ChatMessage(role:.user,text:"explicitly authorized")]),key:"fixture").httpMethod == "POST")
    }
}
