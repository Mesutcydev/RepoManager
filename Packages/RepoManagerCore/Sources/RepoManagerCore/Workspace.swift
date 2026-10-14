import Foundation

public struct DiffHunk: Codable, Equatable, Sendable, Identifiable {
    public var id: Int; public var start: Int; public var removed: [String]; public var added: [String]
}
public enum TextDiff {
    public static func hunks(original: String, updated: String) -> [DiffHunk] {
        let a = original.components(separatedBy:"\n"), b = updated.components(separatedBy:"\n")
        guard a != b else { return [] }
        guard a.count * b.count <= 2_000_000 else { return [DiffHunk(id:0,start:0,removed:a,added:b)] }
        var table = [[Int]](repeating:[Int](repeating:0,count:b.count+1),count:a.count+1)
        for i in stride(from:a.count-1,through:0,by:-1) { for j in stride(from:b.count-1,through:0,by:-1) { table[i][j] = a[i] == b[j] ? table[i+1][j+1]+1 : max(table[i+1][j],table[i][j+1]) } }
        var i = 0, j = 0; var output: [DiffHunk] = []; var pending: DiffHunk?
        while i < a.count || j < b.count {
            if i < a.count && j < b.count && a[i] == b[j] {
                if let p = pending { output.append(p); pending = nil }; i += 1; j += 1
            } else {
                if pending == nil { pending = DiffHunk(id:output.count,start:i,removed:[],added:[]) }
                if j < b.count && (i == a.count || table[i][j+1] >= table[i+1][j]) { pending?.added.append(b[j]); j += 1 }
                else { pending?.removed.append(a[i]); i += 1 }
            }
        }
        if let p = pending { output.append(p) }; return output
    }
    public static func apply(_ hunks: [DiffHunk], to original: String) throws -> String {
        var lines = original.components(separatedBy:"\n"); var previousStart = Int.max
        for h in hunks.sorted(by:{ $0.start > $1.start }) {
            guard h.start >= 0, h.start+h.removed.count <= lines.count, h.start+h.removed.count <= previousStart,
                  Array(lines[h.start..<h.start+h.removed.count]) == h.removed else { throw RMError.conflict }
            lines.replaceSubrange(h.start..<h.start+h.removed.count,with:h.added); previousStart = h.start
        }
        return lines.joined(separator:"\n")
    }
    public static func threeWay(base: String, ours: String, theirs: String) throws -> String {
        if ours == theirs { return ours }; if ours == base { return theirs }; if theirs == base { return ours }
        let a = hunks(original:base,updated:ours), b = hunks(original:base,updated:theirs)
        var merged = a
        for h in b {
            if a.contains(where:{ $0.start == h.start && $0.removed == h.removed && $0.added == h.added }) { continue }
            for other in a {
                let lower = max(h.start,other.start), upper = min(h.start+max(1,h.removed.count),other.start+max(1,other.removed.count))
                if lower < upper { throw RMError.conflict }
            }
            merged.append(h)
        }
        return try apply(merged,to:base)
    }
    public static func review(_ change: FileChange) -> String {
        let operation = change.original == nil ? "Added file" : change.updated == nil ? "Deleted file" : "Modified file"
        let heading = "\(operation): \(change.path)\n"
        let modeNotice = change.originalMode != nil && change.originalMode != change.mode ? "Mode: \(change.originalMode!) → \(change.mode)\n" : ""
        let before = change.original.flatMap { String(data:$0,encoding:.utf8) }, after = change.updated.flatMap { String(data:$0,encoding:.utf8) }
        guard change.original == nil || before != nil, change.updated == nil || after != nil else {
            return heading+modeNotice+"Binary \(change.path)\nBefore: \(change.original?.count ?? 0) bytes · \(change.original.map(RecordCrypto.digest) ?? "absent")\nAfter: \(change.updated?.count ?? 0) bytes · \(change.updated.map(RecordCrypto.digest) ?? "deleted")"
        }
        let hunks = hunks(original:before ?? "",updated:after ?? "")
        let text = hunks.map { h in "@@ line \(h.start+1) @@\n" + h.removed.map { "-"+$0 }.joined(separator:"\n") + "\n" + h.added.map { "+"+$0 }.joined(separator:"\n") }.joined(separator:"\n")
        return heading+modeNotice+RepositorySecretScanner.scan(text).redacted
    }
}

public enum UnifiedPatch {
    public struct File: Sendable { public var path: String; public var delete: Bool; public var create: Bool; public var hunks: [DiffHunk] }
    public static func parse(_ patch: String) throws -> [File] {
        guard patch.utf8.count <= 1024*1024 else { throw RMError.tooLarge }
        let lines = patch.components(separatedBy:"\n"); var i = 0; var files: [File] = []
        let regex = try NSRegularExpression(pattern:#"^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@(?:.*)$"#)
        while i < lines.count {
            if lines[i].isEmpty || lines[i].hasPrefix("diff --git ") || lines[i].hasPrefix("index ") { i += 1; continue }
            guard lines[i].hasPrefix("--- "), i+1 < lines.count, lines[i+1].hasPrefix("+++ ") else { throw RMError.invalidInput }
            let old = String(lines[i].dropFirst(4)), new = String(lines[i+1].dropFirst(4)); i += 2
            let oldPath = old.hasPrefix("a/") ? String(old.dropFirst(2)) : old
            let newPath = new.hasPrefix("b/") ? String(new.dropFirst(2)) : new
            guard oldPath == newPath || old == "/dev/null" || new == "/dev/null" else { throw RMError.unsupported }
            let path = try InputValidation.path(new == "/dev/null" ? oldPath : newPath)
            var hunks: [DiffHunk] = []
            while i < lines.count && lines[i].hasPrefix("@@") {
                let header = lines[i] as NSString
                guard let m = regex.firstMatch(in:lines[i],range:NSRange(location:0,length:header.length)) else { throw RMError.invalidInput }
                func n(_ group: Int, default value: Int) -> Int { m.range(at:group).location == NSNotFound ? value : Int(header.substring(with:m.range(at:group))) ?? value }
                let start = n(1,default:1), oldCount = n(2,default:1), newCount = n(4,default:1)
                i += 1; var removed: [String] = [], added: [String] = []; var oldSeen = 0, newSeen = 0
                while i < lines.count && (oldSeen < oldCount || newSeen < newCount) {
                    let line = lines[i]; i += 1
                    if line.hasPrefix(" ") { removed.append(String(line.dropFirst())); added.append(String(line.dropFirst())); oldSeen += 1; newSeen += 1 }
                    else if line.hasPrefix("-") { removed.append(String(line.dropFirst())); oldSeen += 1 }
                    else if line.hasPrefix("+") { added.append(String(line.dropFirst())); newSeen += 1 }
                    else { throw RMError.invalidInput }
                }
                guard oldSeen == oldCount, newSeen == newCount else { throw RMError.invalidInput }
                if i < lines.count && lines[i].hasPrefix("\\ No newline") { throw RMError.unsupported }
                hunks.append(DiffHunk(id:hunks.count,start:max(0,start-1),removed:removed,added:added))
            }
            guard !hunks.isEmpty, !files.contains(where:{ $0.path == path }) else { throw RMError.invalidInput }
            files.append(File(path:path,delete:new == "/dev/null",create:old == "/dev/null",hunks:hunks))
        }
        guard !files.isEmpty, files.count <= 30 else { throw RMError.tooLarge }; return files
    }
}

public struct MergeConflict: Codable, Identifiable, Sendable {
    public var id: String { path }; public var path: String; public var base: Data?; public var ours: Data?; public var theirs: Data?
}
public actor GitHubWorkspace {
    private struct State: Codable, Sendable {
        var drafts: [UUID:WorkspaceDraft]; var checkpoints: [Checkpoint]
        var mergeParents: [UUID:String]; var conflicts: [UUID:[MergeConflict]]
    }
    private let github: GitHubClient; private let vault: SecureStore; private let approvals: ApprovalCoordinator
    private var drafts: [UUID:WorkspaceDraft] = [:]; private var checkpoints: [Checkpoint] = []
    private var mergeParents: [UUID:String] = [:]; private var conflicts: [UUID:[MergeConflict]] = [:]
    private var unsaved = Set<UUID>()
    private var epoch: UInt64 = 0
    private var openings: [UUID:UUID] = [:]
    public init(github: GitHubClient, vault: SecureStore, approvals: ApprovalCoordinator) { self.github = github; self.vault = vault; self.approvals = approvals }
    public func restore() async throws {
        let lease = epoch
        if let state = try await vault.load(State.self,id:"workspace-state") {
            try Task.checkCancellation(); guard lease == epoch else { throw RMError.cancelled }
            drafts = state.drafts; checkpoints = state.checkpoints
            mergeParents = state.mergeParents; conflicts = state.conflicts
        } else {
            let loadedDrafts = try await vault.load([UUID:WorkspaceDraft].self,id:"drafts") ?? [:]
            let loadedCheckpoints = try await vault.load([Checkpoint].self,id:"checkpoints") ?? []
            let loadedParents = try await vault.load([UUID:String].self,id:"merge-parents") ?? [:]
            let loadedConflicts = try await vault.load([UUID:[MergeConflict]].self,id:"merge-conflicts") ?? [:]
            try Task.checkCancellation(); guard lease == epoch else { throw RMError.cancelled }
            drafts = loadedDrafts; checkpoints = loadedCheckpoints; mergeParents = loadedParents; conflicts = loadedConflicts
        }
        for draft in drafts.values { await approvals.draftChanged(draft.conversationID,revision:draft.revision) }
    }
    public func currentDraft(_ id: UUID) -> WorkspaceDraft? { drafts[id] }
    public func clearMemory() { epoch &+= 1; openings.removeAll(); drafts.removeAll(); checkpoints.removeAll(); mergeParents.removeAll(); conflicts.removeAll(); unsaved.removeAll() }
    public func allDrafts() -> [WorkspaceDraft] { Array(drafts.values) }
    public func allCheckpoints() -> [Checkpoint] { checkpoints }
    public func importDrafts(_ imported: [WorkspaceDraft], checkpoints importedCheckpoints: [Checkpoint]) async throws {
        guard imported.count <= 1000, importedCheckpoints.count <= 1000,
              Set(imported.map(\.conversationID)).count == imported.count,
              Set(importedCheckpoints.map(\.id)).count == importedCheckpoints.count else { throw RMError.corruptRecord }
        var newDrafts: [UUID:WorkspaceDraft] = [:]; var newCheckpoints: [Checkpoint] = []
        for d in imported {
            guard drafts[d.conversationID] == nil else { throw RMError.conflict }
            newDrafts[d.conversationID] = try validated(d)
        }
        for c in importedCheckpoints {
            guard !checkpoints.contains(where:{ $0.id == c.id }), let d = newDrafts[c.draft.conversationID], d.scope == c.draft.scope else { throw RMError.corruptRecord }
            var copy = c; copy.draft = try validated(c.draft); newCheckpoints.append(copy)
        }
        drafts.merge(newDrafts,uniquingKeysWith:{ _,new in new }); checkpoints += newCheckpoints
        unsaved.formUnion(newDrafts.keys); try await persist(); unsaved.subtract(newDrafts.keys)
        for draft in newDrafts.values { await approvals.draftChanged(draft.conversationID,revision:draft.revision) }
    }
    public func mergeConflicts(_ id: UUID) -> [MergeConflict] { conflicts[id] ?? [] }
    public func open(_ scope: RepositoryScope, conversationID: UUID) async throws -> WorkspaceDraft {
        if let d = drafts[conversationID] {
            guard d.scope == scope else { throw RMError.conflict }; return d
        }
        let lease = epoch; let ticket = UUID(); openings[conversationID] = ticket
        _ = try await github.verify(scope,allowOffline:true)
        let draft = WorkspaceDraft(conversationID:conversationID,scope:scope,baseSHA:try await github.head(scope,allowOffline:true))
        try Task.checkCancellation()
        guard lease == epoch else { throw RMError.cancelled }
        if let existing = drafts[conversationID] { guard existing.scope == scope else { throw RMError.conflict }; return existing }
        guard openings[conversationID] == ticket else { throw RMError.cancelled }
        openings[conversationID] = nil
        try await save(draft); return draft
    }
    public func reconnectDraft(_ id: UUID, scope: RepositoryScope) async throws {
        guard var d = drafts[id], d.scope.repositoryID == scope.repositoryID,
              d.scope.branch == scope.branch else { throw RMError.forbidden }
        _ = try await github.verify(scope); try stillCurrent(d)
        for i in checkpoints.indices where checkpoints[i].draft.conversationID == id && checkpoints[i].draft.scope == d.scope {
            checkpoints[i].draft.scope = scope; checkpoints[i].draft.revision = UUID()
        }
        d.scope = scope; d.revision = UUID(); try await save(d)
    }
    public func read(_ path: String, scope: RepositoryScope, conversationID: UUID) async throws -> FileChange {
        let clean = try InputValidation.path(path)
        let draft = try await open(scope,conversationID:conversationID)
        if let c = draft.changes.first(where:{ $0.path == clean }) { return c }
        return try await github.file(scope,path:clean,sha:draft.baseSHA)
    }
    public func stage(_ path: String, bytes: Data?, scope: RepositoryScope, conversationID: UUID, mode: RunMode) async throws {
        guard mode == .act else { throw RMError.forbidden }
        var d = try await open(scope,conversationID:conversationID)
        let original = try await read(path,scope:scope,conversationID:conversationID)
        try stillCurrent(d)
        let change = FileChange(path:try InputValidation.path(path),original:original.original,updated:bytes,mode:original.mode,originalMode:original.originalMode)
        try accept(change,into:&d); d.revision = UUID(); try await save(d)
    }
    public func move(_ path: String, destination: String, scope: RepositoryScope, conversationID: UUID, mode: RunMode) async throws {
        guard mode == .act, path != destination else { throw RMError.forbidden }
        var d = try await open(scope,conversationID:conversationID)
        let old = try await read(path,scope:scope,conversationID:conversationID), target = try await read(destination,scope:scope,conversationID:conversationID)
        guard let bytes = old.updated, target.updated == nil else { throw RMError.conflict }
        try stillCurrent(d)
        try accept(FileChange(path:try InputValidation.path(destination),original:target.original,updated:bytes,mode:old.mode),into:&d)
        try accept(FileChange(path:path,original:old.original,updated:nil,mode:old.mode,originalMode:old.originalMode),into:&d)
        d.revision = UUID(); try await save(d)
    }
    public func patch(_ patch: String, scope: RepositoryScope, conversationID: UUID, mode: RunMode) async throws {
        guard mode == .act else { throw RMError.forbidden }
        var d = try await open(scope,conversationID:conversationID)
        for file in try UnifiedPatch.parse(patch) {
            let current = try await read(file.path,scope:scope,conversationID:conversationID)
            guard !file.create || current.updated == nil else { throw RMError.conflict }
            guard current.updated == nil || String(data:current.updated!,encoding:.utf8) != nil else { throw RMError.unsupported }
            let source = current.updated.flatMap { String(data:$0,encoding:.utf8) } ?? ""
            let updated = try TextDiff.apply(file.hunks,to:source)
            try accept(FileChange(path:file.path,original:current.original,updated:file.delete ? nil : Data(updated.utf8),mode:current.mode,originalMode:current.originalMode),into:&d)
        }
        try stillCurrent(d)
        d.revision = UUID(); try await save(d)
    }
    public func selectHunks(_ indexes: Set<Int>, path: String, conversationID: UUID) async throws {
        guard var d = drafts[conversationID], let i = d.changes.firstIndex(where:{ $0.path == path }),
              let before = d.changes[i].original.flatMap({ String(data:$0,encoding:.utf8) }), let after = d.changes[i].updated.flatMap({ String(data:$0,encoding:.utf8) }) else { throw RMError.unsupported }
        let hunks = TextDiff.hunks(original:before,updated:after)
        guard indexes.isSubset(of:Set(hunks.map(\.id))) else { throw RMError.invalidInput }
        let changed = try TextDiff.apply(hunks.filter { indexes.contains($0.id) },to:before)
        d.changes[i].updated = Data(changed.utf8)
        d.changes.removeAll { $0.original == $0.updated && ($0.originalMode ?? $0.mode) == $0.mode }
        d.revision = UUID(); try await save(d)
    }
    public func checkpoint(_ id: UUID, title: String) async throws -> Checkpoint {
        guard let draft = drafts[id] else { throw RMError.unavailable }
        let c = Checkpoint(title:String(title.prefix(200)),draft:draft); checkpoints.append(c)
        try await persist(); return c
    }
    public func restoreCheckpoint(_ checkpointID: UUID, conversationID: UUID) async throws {
        guard let c = checkpoints.first(where:{ $0.id == checkpointID }), c.draft.conversationID == conversationID,
              c.draft.scope == drafts[conversationID]?.scope else { throw RMError.forbidden }
        var draft = c.draft; draft.revision = UUID(); try await save(draft)
    }
    public func prepare(_ id: UUID, message: String) async throws -> MutationPlan {
        guard let d = drafts[id], !unsaved.contains(id), (conflicts[id] ?? []).isEmpty else { throw RMError.conflict }
        return try await approvals.prepareCommit(draft:d,message:message,mergeParent:mergeParents[id])
    }
    public func discard(_ id: UUID) async throws {
        openings[id] = nil
        drafts[id] = nil; conflicts[id] = nil; mergeParents[id] = nil
        await approvals.invalidate(conversationID:id); try await persist()
    }
    public func markPublished(_ plan: MutationPlan) async throws {
        guard let d = drafts[plan.conversationID], d.revision == plan.draft?.revision else { return }
        try await discard(plan.conversationID)
    }
    public func restage(_ id: UUID) async throws {
        guard var d = drafts[id] else { throw RMError.unavailable }
        let head = try await github.head(d.scope); var changes: [FileChange] = []; var newConflicts: [MergeConflict] = []
        for c in d.changes {
            let remote = try await github.file(d.scope,path:c.path,sha:head)
            do {
                let updated = try merge(base:c.original,ours:c.updated,theirs:remote.updated)
                let mode = try Self.mergeMode(base:c.original == nil ? nil : c.originalMode ?? c.mode,ours:c.updated == nil ? nil : c.mode,theirs:remote.updated == nil ? nil : remote.mode) ?? remote.mode
                changes.append(FileChange(path:c.path,original:remote.updated,updated:updated,mode:mode,originalMode:remote.originalMode))
            } catch RMError.conflict {
                newConflicts.append(MergeConflict(path:c.path,base:c.original,ours:c.updated,theirs:remote.updated))
                changes.append(FileChange(path:c.path,original:remote.updated,updated:c.updated,mode:c.mode,originalMode:remote.originalMode))
            }
        }
        try stillCurrent(d)
        d.baseSHA = head; d.changes = changes; d.revision = UUID(); conflicts[id] = newConflicts; try await save(d)
    }
    public func resolveConflict(_ id: UUID, path: String, bytes: Data?) async throws {
        guard var d = drafts[id], conflicts[id]?.contains(where:{ $0.path == path }) == true else { throw RMError.invalidInput }
        guard let existing = d.changes.first(where:{ $0.path == path }) else { throw RMError.invalidInput }
        try accept(FileChange(path:path,original:existing.original,updated:bytes,mode:existing.mode,originalMode:existing.originalMode),into:&d)
        conflicts[id]?.removeAll { $0.path == path }; d.revision = UUID(); try await save(d)
    }
    public func prepareMerge(headRef: String, scope: RepositoryScope, conversationID: UUID) async throws -> WorkspaceDraft {
        _ = try InputValidation.ref(headRef)
        var d = try await open(scope,conversationID:conversationID)
        guard d.changes.isEmpty else { throw RMError.conflict }
        let comparison = try await github.get(scope,path:github.repo(scope)+"/compare/\(scope.branch)...\(headRef)")
        guard let base = comparison["merge_base_commit"]["sha"].string, let theirs = comparison["commits"].array?.last?["sha"].string else { throw RMError.conflict }
        let changed = try await changedPaths(scope,from:base,to:theirs)
        var newConflicts: [MergeConflict] = []
        for path in changed {
            let old = try await github.file(scope,path:path,sha:base), ours = try await github.file(scope,path:path,sha:d.baseSHA), remote = try await github.file(scope,path:path,sha:theirs)
            do {
                let mode = try Self.mergeMode(base:old.updated == nil ? nil : old.mode,ours:ours.updated == nil ? nil : ours.mode,theirs:remote.updated == nil ? nil : remote.mode) ?? ours.mode
                try accept(FileChange(path:path,original:ours.updated,updated:merge(base:old.updated,ours:ours.updated,theirs:remote.updated),mode:mode,originalMode:ours.originalMode),into:&d)
            }
            catch RMError.conflict {
                newConflicts.append(MergeConflict(path:path,base:old.updated,ours:ours.updated,theirs:remote.updated))
                d.changes.append(FileChange(path:path,original:ours.updated,updated:ours.updated,mode:ours.mode))
            }
        }
        try stillCurrent(d)
        conflicts[conversationID] = newConflicts; mergeParents[conversationID] = theirs; d.revision = UUID(); try await save(d); return d
    }
    public func forwardRevert(scope: RepositoryScope, conversationID: UUID, message: String) async throws -> MutationPlan {
        var d = try await open(scope,conversationID:conversationID); guard d.changes.isEmpty else { throw RMError.conflict }
        let commit = try await github.get(scope,path:github.repo(scope)+"/git/commits/\(d.baseSHA)")
        guard let parents = commit["parents"].array, parents.count == 1, let parent = parents[0]["sha"].string else { throw RMError.unsupported }
        for path in try await changedPaths(scope,from:parent,to:d.baseSHA) {
            let old = try await github.file(scope,path:path,sha:parent), current = try await github.file(scope,path:path,sha:d.baseSHA)
            try accept(FileChange(path:path,original:current.updated,updated:old.updated,mode:old.updated == nil ? current.mode : old.mode,originalMode:current.originalMode),into:&d)
        }
        try stillCurrent(d)
        d.revision = UUID(); try await save(d); return try await prepare(conversationID,message:message)
    }
    private func changedPaths(_ scope: RepositoryScope, from: String, to: String) async throws -> [String] {
        let a = try await github.tree(scope,sha:from), b = try await github.tree(scope,sha:to)
        guard a["truncated"].bool != true, b["truncated"].bool != true else { throw RMError.tooLarge }
        func entries(_ tree: JSON) -> [String:JSON] { Dictionary((tree["tree"].array ?? []).compactMap { e in e["type"].string == "blob" ? e["path"].string.map { ($0,e) } : nil },uniquingKeysWith:{ a,_ in a }) }
        let old = entries(a), new = entries(b)
        let paths = Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
        guard paths.count <= 30 else { throw RMError.tooLarge }; return paths
    }
    private func merge(base: Data?, ours: Data?, theirs: Data?) throws -> Data? {
        if ours == theirs { return ours }; if ours == base { return theirs }; if theirs == base { return ours }
        guard let base, let ours, let theirs, let b = String(data:base,encoding:.utf8), let o = String(data:ours,encoding:.utf8), let t = String(data:theirs,encoding:.utf8) else { throw RMError.conflict }
        return Data(try TextDiff.threeWay(base:b,ours:o,theirs:t).utf8)
    }
    private func accept(_ change: FileChange, into draft: inout WorkspaceDraft) throws {
        _ = try InputValidation.path(change.path); guard ["100644","100755"].contains(change.mode) else { throw RMError.unsupported }
        if let data = change.updated {
            if let text = String(data:data,encoding:.utf8) { guard data.count <= 256*1024, RepositorySecretScanner.scan(text).findings.isEmpty else { throw RMError.forbidden } }
            else { guard data.count <= 1024*1024 else { throw RMError.tooLarge } }
        }
        draft.changes.removeAll { $0.path == change.path }
        if change.original != change.updated || change.original != nil && (change.originalMode ?? change.mode) != change.mode { draft.changes.append(change) }
        guard draft.changes.count <= 30, draft.changes.reduce(0,{ $0+($1.original?.count ?? 0)+($1.updated?.count ?? 0) }) <= 2*1024*1024 else { throw RMError.tooLarge }
    }
    static func mergeMode(base: String?, ours: String?, theirs: String?) throws -> String? {
        if ours == theirs { return ours }; if ours == base { return theirs }; if theirs == base { return ours }
        throw RMError.conflict
    }
    private func stillCurrent(_ draft: WorkspaceDraft) throws {
        guard drafts[draft.conversationID]?.revision == draft.revision, drafts[draft.conversationID]?.scope == draft.scope else { throw RMError.conflict }
    }
    private func validated(_ draft: WorkspaceDraft) throws -> WorkspaceDraft {
        guard draft.scope.repositoryID > 0 else { throw RMError.corruptRecord }
        _ = try InputValidation.component(draft.scope.owner); _ = try InputValidation.component(draft.scope.name); _ = try InputValidation.ref(draft.scope.branch)
        var copy = WorkspaceDraft(conversationID:draft.conversationID,scope:draft.scope,baseSHA:try InputValidation.sha(draft.baseSHA))
        for change in draft.changes { try accept(change,into:&copy) }; return copy
    }
    private func save(_ draft: WorkspaceDraft) async throws {
        try Task.checkCancellation(); let lease = epoch
        drafts[draft.conversationID] = draft; unsaved.insert(draft.conversationID)
        await approvals.draftChanged(draft.conversationID,revision:draft.revision)
        guard lease == epoch,drafts[draft.conversationID]?.revision == draft.revision else { throw RMError.cancelled }
        try Task.checkCancellation()
        try await persist(); unsaved.remove(draft.conversationID)
    }
    private func persist() async throws {
        try await vault.save(State(drafts:drafts,checkpoints:checkpoints,mergeParents:mergeParents,conflicts:conflicts),id:"workspace-state")
    }
}
