import Foundation

/// A person's report about a model response, composed for their own mail app.
/// Repo Manager sends nothing itself; the person reviews, edits, or discards the message there.
public enum ContentReport {
    public static let reasons = [String(localized:"Inaccurate or misleading",bundle:.module),String(localized:"Harmful or offensive",bundle:.module),String(localized:"Exposes private or sensitive data",bundle:.module),String(localized:"Something else",bundle:.module)]
    public static let excerptLimit = 1500
    public static func mailURL(to address:String,reason:String,note:String,source:String,messageID:UUID,created:Date,response:String?) -> URL? {
        guard address.contains("@"), !address.contains(where:{ $0.isWhitespace || "?&/".contains($0) }) else { return nil }
        var body = "Reason: \(reason)\nModel: \(source.isEmpty ? "unknown" : source)\nResponse ID: \(messageID.uuidString)\nResponse time: \(created.formatted(.iso8601))\n"
        let note = note.trimmingCharacters(in:.whitespacesAndNewlines)
        if !note.isEmpty { body += "\nWhat happened:\n\(note.prefix(2000))\n" }
        if let response {
            let masked = RepositorySecretScanner.scan(response).redacted
            body += "\nResponse (credentials masked\(masked.count > excerptLimit ? "; first 1,500 characters" : "")):\n\(masked.prefix(excerptLimit))\n"
        }
        // `&`, `=`, `+`, `?` and `#` must be escaped inside mailto fields or the mail app splits the body.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn:"&=+?#"))
        func field(_ value:String) -> String { value.addingPercentEncoding(withAllowedCharacters:allowed) ?? "" }
        return URL(string:"mailto:\(address)?subject=\(field("Repo Manager response report: \(reason)"))&body=\(field(body))")
    }
}
