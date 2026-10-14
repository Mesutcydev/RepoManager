import UIKit
import UniformTypeIdentifiers
import RepoManagerCore

final class ShareViewController: UIViewController {
    private let label = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        label.text = "Encrypting for Repo Manager…"; label.numberOfLines = 0; label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo:view.centerXAnchor),label.centerYAnchor.constraint(equalTo:view.centerYAnchor),label.widthAnchor.constraint(lessThanOrEqualTo:view.widthAnchor,multiplier:0.8)])
        Task { await ingest() }
    }
    @MainActor private func ingest() async {
        do {
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:SharedInbox.group) else { throw RMError.unavailable }
            let root = container.appendingPathComponent("EncryptedInbox",isDirectory:true)
            let publicKey = try BoundedFile.read(root.appendingPathComponent("public-key"),limit:32)
            let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] } ?? []
            guard items.count <= 3 else { throw RMError.tooLarge }
            for item in items {
                let payload: SharePayload
                if item.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let text = try await loadText(item); payload = SharePayload(text:text,name:"Shared text")
                } else if item.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let url = try await loadURL(item); guard url.scheme == "https", url.user == nil, url.password == nil else { throw RMError.insecureURL }
                    payload = SharePayload(text:url.absoluteString,name:"Shared URL")
                } else {
                    let supported: [UTType] = [.pdf,.text,.json,.sourceCode]
                    guard let type = supported.first(where:{ item.hasItemConformingToTypeIdentifier($0.identifier) }) else { throw RMError.unsupported }
                    // loadDataRepresentation transfers bytes into memory; no app-owned plaintext temporary copy.
                    let data = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data,Error>) in
                        item.loadDataRepresentation(forTypeIdentifier:type.identifier) { data,error in
                            if let data { c.resume(returning:data) } else { c.resume(throwing:RMError.unsupported) }
                        }
                    }
                    guard data.count <= (type == .pdf ? 32*1024*1024 : 128*1024) else { throw RMError.tooLarge }
                    payload = SharePayload(text:"",name:type == .pdf ? "Shared.pdf" : "Shared.txt",document:data)
                }
                let encrypted = try SharedInbox.encrypt(payload,publicKey:publicKey)
                let output = root.appendingPathComponent(encrypted.id.uuidString).appendingPathExtension("rminbox")
                try JSONEncoder().encode(encrypted).write(to:output,options:[.atomic,.completeFileProtection])
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:output.path)
            }
            label.text = "Encrypted. Open Repo Manager to import."
            extensionContext?.completeRequest(returningItems:nil)
        } catch { label.text = (error as? RMError ?? .unavailable).localizedDescription }
    }
    private func loadText(_ item: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { c in item.loadItem(forTypeIdentifier:UTType.plainText.identifier,options:nil) { value,_ in
            if let text = value as? String { c.resume(returning:text) } else { c.resume(throwing:RMError.unsupported) }
        } }
    }
    private func loadURL(_ item: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { c in item.loadItem(forTypeIdentifier:UTType.url.identifier,options:nil) { value,_ in
            if let url = value as? URL { c.resume(returning:url) } else { c.resume(throwing:RMError.unsupported) }
        } }
    }
}
