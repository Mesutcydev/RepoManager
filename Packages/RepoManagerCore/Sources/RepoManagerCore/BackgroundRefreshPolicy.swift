import Foundation

public enum BackgroundRefreshPolicy {
    /// Repositories must have an explicit saved scope and the same live connection identity.
    public static func scopes(_ data:AppData) -> [RepositoryScope] {
        guard data.preferences.backgroundNetworkRefresh == true else { return [] }
        let accounts = Dictionary(data.accounts.map { ($0.id,$0.connectionID) },uniquingKeysWith:{ first,_ in first })
        var seen = Set<RepositoryScope>(); var output: [RepositoryScope] = []
        for conversation in data.conversations.sorted(by:{ $0.modified > $1.modified }) where !conversation.archived {
            if let scope = conversation.repository,accounts[scope.accountID] == scope.connectionID,seen.insert(scope).inserted {
                output.append(scope); if output.count == 3 { break }
            }
        }
        return output
    }
}
