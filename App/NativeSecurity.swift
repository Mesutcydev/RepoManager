import Foundation
import LocalAuthentication
import RepoManagerCore
import UIKit

struct AppleAuthenticator: NativeAuthenticator {
    func authenticate(action: String, target: String) async throws -> Bool {
        let context = LAContext(); context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication,error:&error) else { throw RMError.unavailable }
        let authentication = AuthenticationContext(context)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let approved = try await context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"Approve \(action.replacingOccurrences(of:"_",with:" ")) for \(target)")
            try Task.checkCancellation(); return approved
        } onCancel: { authentication.invalidate() }
    }
}
private final class AuthenticationContext: @unchecked Sendable {
    private let context:LAContext
    init(_ context:LAContext) { self.context = context }
    func invalidate() { context.invalidate() }
}
@MainActor enum SafeClipboard {
    static func copyResponse(_ text: String) {
        let value = RepositorySecretScanner.scan(text).redacted
        UIPasteboard.general.setItems([["public.utf8-plain-text":value]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(60)])
    }
}
