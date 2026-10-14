import Foundation

public struct DeviceAuthorization: Equatable, Sendable {
    public var userCode: String; public var verificationURL: URL; public var deviceCode: String
    public var expires: Date; public var interval: Int
}
private struct GitHubCredentials: Codable, Sendable {
    var access: String; var refresh: String?; var expires: Date?; var refreshExpires: Date?; var clientID: String?
    var connectionID:UUID?
}
public actor GitHubConnectionStore {
    private let secrets: any SecretStore; private let transport: any HTTPTransport; private let vault: SecureStore
    private var accounts: [GitHubAccount] = []
    private var refreshing: [Int64:(id:UUID,task:Task<String,Error>)] = [:]
    private var epoch:UInt64 = 0
    private let pollWait:@Sendable (Int) async throws -> Void
    public init(vault: SecureStore, secrets: any SecretStore = KeychainStore(), transport: any HTTPTransport = SecureHTTPTransport(),pollWait:@escaping @Sendable (Int) async throws -> Void = { try await Task.sleep(for:.seconds($0)) }) {
        self.vault = vault; self.secrets = secrets; self.transport = transport; self.pollWait = pollWait
    }
    public func restore() async throws -> [GitHubAccount] {
        let lease = epoch; let restored = try await vault.load([GitHubAccount].self,id:"github-accounts") ?? []
        try Task.checkCancellation(); guard lease == epoch else { throw RMError.cancelled }
        accounts = restored; return accounts
    }
    public func savedAccounts() -> [GitHubAccount] { accounts }
    public func beginDeviceFlow(clientID: String) async throws -> DeviceAuthorization {
        guard GitHubAppConfiguration.validClientID(clientID) else { throw GitHubPairingError.configurationUnavailable }
        let lease = epoch
        try Task.checkCancellation()
        let result = try await oauth("device/code", fields:["client_id":clientID,"scope":"offline_access"])
        try Task.checkCancellation()
        guard lease == epoch else { throw RMError.cancelled }
        if let error = result["error"].string { throw GitHubPairingError.fromOAuth(error) }
        guard let code = result["device_code"].string, let user = result["user_code"].string,
              !code.isEmpty, code.utf8.count <= 1024,
              (6...32).contains(user.utf8.count), user.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 45 }),
              let rawURL = result["verification_uri"].string, let url = URL(string: rawURL),
              url.host == "github.com", url.scheme == "https", url.path == "/login/device",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              let expiry = result["expires_in"].int, (1...1800).contains(expiry),
              (1...60).contains(result["interval"].int ?? 5) else { throw GitHubPairingError.invalidResponse }
        return DeviceAuthorization(userCode:user,verificationURL:url,deviceCode:code,expires:Date().addingTimeInterval(Double(expiry)),interval:max(1,result["interval"].int ?? 5))
    }
    public func completeDeviceFlow(_ flow: DeviceAuthorization, clientID: String,
                                   onIntervalChange: @escaping @Sendable (Int) async -> Void = { _ in }) async throws -> GitHubAccount {
        guard GitHubAppConfiguration.validClientID(clientID), (1...1800).contains(flow.interval),
              !flow.deviceCode.isEmpty, flow.deviceCode.utf8.count <= 1024 else { throw GitHubPairingError.invalidResponse }
        try Task.checkCancellation()
        var interval = flow.interval; let lease = epoch
        while Date() < flow.expires {
            try Task.checkCancellation()
            guard lease == epoch else { throw RMError.cancelled }
            // A server slowdown must not keep an expired attempt busy beyond
            // its original deadline. No further request is made at expiry.
            let wait = max(1, min(Double(interval), ceil(flow.expires.timeIntervalSinceNow)))
            try await pollWait(Int(wait))
            try Task.checkCancellation()
            guard lease == epoch else { throw RMError.cancelled }
            guard Date() < flow.expires else { throw GitHubPairingError.expired }
            let response = try await oauth("oauth/access_token", fields:["client_id":clientID,"device_code":flow.deviceCode,"grant_type":"urn:ietf:params:oauth:grant-type:device_code"])
            try Task.checkCancellation()
            guard lease == epoch else { throw RMError.cancelled }
            guard Date() < flow.expires else { throw GitHubPairingError.expired }
            switch response["error"].string {
            case "authorization_pending": continue
            case "slow_down":
                let reported = response["interval"].int ?? 0
                guard (0...1800).contains(reported) else { throw GitHubPairingError.invalidResponse }
                interval = min(1800, max(interval + 5, reported))
                await onIntervalChange(interval)
                continue
            case .some(let error): throw GitHubPairingError.fromOAuth(error)
            case nil: return try await install(response, clientID: clientID,lease:lease)
            }
        }
        throw GitHubPairingError.expired
    }
    public func connectPAT(_ value: String) async throws -> GitHubAccount {
        guard value.hasPrefix("github_pat_"), value.count >= 30, value.count <= 255 else { throw RMError.invalidInput }
        return try await install(.object(["access_token":.string(value)]), clientID:nil,lease:epoch)
    }
    private func install(_ response: JSON, clientID: String?,lease:UInt64) async throws -> GitHubAccount {
        guard let access = response["access_token"].string, !access.isEmpty else { throw RMError.authentication }
        var req = URLRequest(url: URL(string:"https://api.github.com/user")!); req.setValue("Bearer \(access)",forHTTPHeaderField:"Authorization")
        let r = try await transport.send(req,limit:256*1024); try SecureHTTPTransport.checkStatus(r.status)
        try Task.checkCancellation(); guard lease == epoch else { throw RMError.cancelled }
        guard let id = r.json["id"].int, let login = r.json["login"].string else { throw RMError.authentication }
        let account = GitHubAccount(id:Int64(id),login:login,expiresAt:response["expires_in"].int.map { Date().addingTimeInterval(Double($0)) },clientID:clientID)
        let credentials = GitHubCredentials(access:access,refresh:response["refresh_token"].string,
            expires:response["expires_in"].int.map { Date().addingTimeInterval(Double($0)) },
            refreshExpires:response["refresh_token_expires_in"].int.map { Date().addingTimeInterval(Double($0)) },clientID:clientID,connectionID:account.connectionID)
        refreshing[Int64(id)]?.task.cancel(); refreshing[Int64(id)] = nil
        // One Keychain item makes access/refresh rotation atomic.
        try secrets.write(JSONEncoder().encode(credentials),account:"github:\(id)")
        accounts.removeAll { $0.id == Int64(id) }; accounts.append(account)
        try await vault.save(accounts,id:"github-accounts")
        return account
    }
    public func token(for scope: RepositoryScope) async throws -> String {
        guard let account = accounts.first(where:{ $0.id == scope.accountID }), account.connectionID == scope.connectionID else { throw RMError.authentication }
        return try await token(accountID: account.id)
    }
    public func token(accountID: Int64) async throws -> String {
        guard let account = accounts.first(where: { $0.id == accountID }), let raw = try secrets.read("github:\(accountID)") else { throw RMError.authentication }
        let c = try JSONDecoder().decode(GitHubCredentials.self,from:raw)
        guard c.connectionID == account.connectionID else { throw RMError.authentication }
        if c.expires == nil || c.expires! > Date().addingTimeInterval(60) { return c.access }
        if let pending = refreshing[accountID] { let token = try await pending.task.value; try Task.checkCancellation(); return token }
        guard let refresh = c.refresh, let client = c.clientID, c.refreshExpires.map({ $0 > Date() }) ?? false else { throw RMError.authentication }
        let refreshID = UUID()
        let task = Task<String,Error> {
            try Task.checkCancellation()
            let result = try await self.oauth("oauth/access_token",fields:["client_id":client,"grant_type":"refresh_token","refresh_token":refresh])
            try Task.checkCancellation()
            guard self.accounts.first(where:{ $0.id == accountID })?.connectionID == account.connectionID else { throw RMError.authentication }
            guard let access = result["access_token"].string, let next = result["refresh_token"].string,
                  let expires = result["expires_in"].int, let refreshExpiry = result["refresh_token_expires_in"].int else { throw RMError.authentication }
            let rotated = GitHubCredentials(access:access,refresh:next,expires:Date().addingTimeInterval(Double(expires)),refreshExpires:Date().addingTimeInterval(Double(refreshExpiry)),clientID:client,connectionID:account.connectionID)
            try self.secrets.write(JSONEncoder().encode(rotated),account:"github:\(accountID)")
            return access
        }
        refreshing[accountID] = (refreshID,task)
        defer { if refreshing[accountID]?.id == refreshID { refreshing[accountID] = nil } }
        let token = try await task.value; try Task.checkCancellation(); return token
    }
    public func disconnect(_ id: Int64) async throws {
        epoch &+= 1
        refreshing[id]?.task.cancel(); refreshing[id] = nil; try secrets.delete("github:\(id)")
        accounts.removeAll { $0.id == id }; try await vault.save(accounts,id:"github-accounts")
    }
    public func cancelRequests() { epoch &+= 1; for pending in refreshing.values { pending.task.cancel() }; refreshing.removeAll() }
    private func oauth(_ path: String, fields: [String:String]) async throws -> JSON {
        var c = URLComponents(); c.queryItems = fields.map { URLQueryItem(name:$0.key,value:$0.value) }
        var request = URLRequest(url:URL(string:"https://github.com/login/\(path)")!)
        request.httpMethod = "POST"; request.httpBody = Data((c.percentEncodedQuery ?? "").utf8)
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type"); request.setValue("application/json",forHTTPHeaderField:"Accept")
        let result = try await transport.send(request,limit:64*1024); try SecureHTTPTransport.checkStatus(result.status)
        return try JSON.parse(result.data)
    }
}

public actor GitHubClient {
    public let connections: GitHubConnectionStore
    let transport: any HTTPTransport; let vault: SecureStore
    public init(connections: GitHubConnectionStore, vault: SecureStore, transport: any HTTPTransport = SecureHTTPTransport()) {
        self.connections = connections; self.transport = transport; self.vault = vault
    }
    public func repositories(accountID: Int64, page: Int = 1) async throws -> JSON {
        let token = try await connections.token(accountID:accountID)
        return try await request(path:"user/repos",token:token,query:["per_page":"100","page":String(max(1,min(page,20))),"sort":"updated"]).json
    }
    /// A repository-creation review has an account identity and a destination name, but no repository ID yet.
    public func creationSnapshot(_ scope: RepositoryScope) async throws -> JSON {
        let token = try await connections.token(for:scope)
        let user = try await request(path:"user",token:token).json
        guard user["id"].int == Int(scope.accountID),user["login"].string?.lowercased() == scope.owner.lowercased() else { throw RMError.authentication }
        do {
            _ = try await request(path:repo(scope),token:token)
            throw RMError.conflict
        } catch RMError.unavailable {
            return .object(["account":.string(scope.owner),"repository":.string(scope.fullName),"exists":false])
        }
    }
    func createRepository(_ plan:MutationPlan,validate:@escaping @Sendable () async throws -> Void) async throws -> JSON {
        let token = try await connections.token(for:plan.scope)
        try await validate()
        let result = try await request(path:"user/repos",token:token,method:"POST",body:plan.arguments["body"]).json
        guard result["id"].int != nil,result["full_name"].string?.lowercased() == plan.scope.fullName.lowercased(),
              result["private"].bool == plan.arguments["body"]["private"].bool else { throw RMError.uncertainWrite }
        return GitHubRedaction.clean(result)
    }
    public func verify(_ scope: RepositoryScope, permission: String = "pull",allowOffline:Bool = false) async throws -> JSON {
        _ = try InputValidation.component(scope.owner); _ = try InputValidation.component(scope.name); _ = try InputValidation.ref(scope.branch)
        let token = try await connections.token(for:scope)
        let cacheID = "repository-identity:\(scope.accountID):\(scope.connectionID):\(scope.repositoryID)"
        var info: JSON
        do {
            info = try await request(path:"repositories/\(scope.repositoryID)",token:token).json
            try await vault.save(info,id:cacheID)
        } catch RMError.connection where allowOffline && permission == "pull" {
            guard let saved = try await vault.load(JSON.self,id:cacheID) else { throw RMError.connection }; info = saved
        }
        guard info["id"].int == Int(scope.repositoryID), info["full_name"].string?.lowercased() == scope.fullName.lowercased() else { throw RMError.conflict }
        // Public repository read permission may be omitted; writes are always explicit.
        if permission != "pull", info["permissions"][permission].bool != true { throw RMError.forbidden }
        return info
    }
    public func head(_ scope: RepositoryScope,allowOffline:Bool = false) async throws -> String {
        let data = try await get(scope,path:repo(scope)+"/git/ref/heads/\(scope.branch)",cache:allowOffline)
        guard let sha = data["object"]["sha"].string else { throw RMError.invalidInput }; return try InputValidation.sha(sha)
    }
    public func get(_ scope: RepositoryScope, path: String, query: [String:String] = [:], cache: Bool = false) async throws -> JSON {
        let key = "cache:\(scope.accountID):\(scope.connectionID):\(scope.repositoryID):\(path):\(query.sorted { $0.key < $1.key })"
        do {
            let result = try await request(path:path,token:connections.token(for:scope),query:query)
            let json = try JSON.parse(result.data)
            if cache { try await vault.save(json,id:key) }; return json
        } catch RMError.connection where cache {
            guard let saved = try await vault.load(JSON.self,id:key) else { throw RMError.connection }; return saved
        }
    }
    public func tree(_ scope: RepositoryScope, sha: String) async throws -> JSON {
        _ = try InputValidation.sha(sha)
        let commit = try await get(scope,path:repo(scope)+"/git/commits/\(sha)",cache:true)
        guard let tree = commit["tree"]["sha"].string else { throw RMError.invalidInput }
        return try await get(scope,path:repo(scope)+"/git/trees/\(tree)",query:["recursive":"1"],cache:true)
    }
    public func file(_ scope: RepositoryScope, path: String, sha: String) async throws -> FileChange {
        _ = try InputValidation.path(path); _ = try InputValidation.sha(sha)
        let tree = try await tree(scope,sha:sha)
        guard tree["truncated"].bool != true else { throw RMError.tooLarge }
        guard let entry = tree["tree"].array?.first(where:{ $0["path"].string == path }) else { return FileChange(path:path,original:nil,updated:nil) }
        guard entry["type"].string == "blob", let mode = entry["mode"].string, ["100644","100755"].contains(mode),
              let blobSHA = entry["sha"].string, (entry["size"].int ?? Int.max) <= 1024*1024 else { throw RMError.unsupported }
        let blob = try await get(scope,path:repo(scope)+"/git/blobs/\(blobSHA)",cache:true)
        guard blob["encoding"].string == "base64", let content = blob["content"].string,
              let bytes = Data(base64Encoded:content,options:.ignoreUnknownCharacters), bytes.count <= 1024*1024 else { throw RMError.tooLarge }
        return FileChange(path:path,original:bytes,updated:bytes,mode:mode)
    }
    public func read(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope) async throws -> JSON {
        try Schema.validate(arguments,against:definition.schema)
        _ = try await verify(scope,permission:definition.permission,allowOffline:definition.risk == .read && definition.permission == "pull")
        if definition.method == "GRAPHQL" { return try await graphRead(definition,arguments:arguments,scope:scope) }
        guard definition.risk == .read else { throw RMError.forbidden }
        if definition.name == "download_artifact" {
            let asset = try await download(scope:scope,kind:"artifact",id:arguments["id"].int ?? 0)
            return try JSON.parse(JSONEncoder().encode(asset))
        }
        if definition.name == "workflow_logs" {
            let asset = try await download(scope:scope,kind:"job_log",id:arguments["id"].int ?? 0)
            let stream = try await vault.assetStream(asset); stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating:0,count:64*1024); let count = stream.read(&bytes,maxLength:bytes.count)
            guard count >= 0 else { throw RMError.corruptRecord }
            return .object(["logs":.string(RepositorySecretScanner.scan(String(decoding:bytes.prefix(count),as:UTF8.self)).redacted),"coverage":"First 64 KiB; encrypted full asset retained."])
        }
        let path = try expanded(definition.path,arguments:arguments,scope:scope)
        var query = ["per_page":"30"]
        if definition.name == "git_log" { query["sha"] = scope.branch; query["path"] = arguments["path"].string }
        if definition.name == "workflow_status" { query["branch"] = scope.branch }
        if let state = arguments["state"].string { query["state"] = state }
        if ["search_code","search_issues","search_pull_requests"].contains(definition.name) {
            guard let q = arguments["query"].string, !q.contains(":"), !q.contains("\n") else { throw RMError.invalidInput }
            query["q"] = "\(q) repo:\(scope.fullName)" + (definition.name == "search_issues" ? " is:issue" : definition.name == "search_pull_requests" ? " is:pr" : "")
        }
        // Secrets/alerts can include sensitive raw values. Strip structural value fields too.
        let result = try await get(scope,path:path,query:query,cache:true)
        return GitHubRedaction.clean(result)
    }
    public func remoteSnapshot(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope) async throws -> JSON {
        let repository = try await verify(scope,permission:definition.permission)
        if ["set_secret","set_environment_secret","set_dependabot_secret"].contains(definition.name) {
            let path = try expanded(definition.path,arguments:arguments,scope:scope)
            do { let metadata = try await get(scope,path:path); return .object(["exists":true,"metadata":GitHubRedaction.clean(metadata)]) }
            catch RMError.unavailable { return .object(["exists":false,"name":arguments["name"]]) }
        }
        if definition.method == "GRAPHQL" { return try await graphMutationSnapshot(definition,arguments:arguments,scope:scope) }
        let path = try expanded(definition.reviewPath ?? definition.path,arguments:arguments,scope:scope)
        let target = try await get(scope,path:path,query:["per_page":"100"])
        if definition.name == "merge_pull_request" {
            let strategy = arguments["body"]["merge_method"].string ?? ""
            let permissionKey = strategy == "squash" ? "allow_squash_merge" : strategy == "rebase" ? "allow_rebase_merge" : "allow_merge_commit"
            guard repository[permissionKey].bool == true else { throw RMError.forbidden }
            guard target["head"]["sha"].string == arguments["body"]["sha"].string,target["state"].string == "open",target["draft"].bool != true else { throw RMError.conflict }
            return .object(["pull_request":target,"merge_strategy":.string(strategy),"strategy_allowed":true])
        }
        if definition.name == "upload_release_asset" {
            guard let id = UUID(uuidString:arguments["asset_id"].string ?? ""), let asset = try await vault.asset(id) else { throw RMError.forbidden }
            return .object(["target":target,"binary_name":.string(asset.name),"binary_bytes":.number(Double(asset.byteCount)),"sha256":.string(asset.sha256)])
        }
        return target
    }
    func mutate(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope, validate:@escaping @Sendable () async throws -> Void) async throws -> JSON {
        guard definition.risk != .read else { throw RMError.forbidden }
        try Schema.validate(arguments,against:definition.schema)
        _ = try await verify(scope,permission:definition.permission)
        if definition.name == "upload_release_asset" {
            guard let id = UUID(uuidString:arguments["asset_id"].string ?? ""), let asset = try await vault.asset(id) else { throw RMError.forbidden }
            return try await uploadAsset(asset,releaseID:arguments["id"].int ?? 0,scope:scope,validate:validate)
        }
        if definition.method == "GRAPHQL" { return try await graphMutate(definition,arguments:arguments,scope:scope,validate:validate) }
        let path = try expanded(definition.path,arguments:arguments,scope:scope)
        let token = try await connections.token(for:scope)
        try await validate()
        let result = try await request(path:path,token:token,method:definition.method,body:arguments["body"])
        var output = result.data.isEmpty ? JSON.object([:]) : GitHubRedaction.clean(result.json)
        if var fields = output.object { fields["http_status"] = .number(Double(result.status)); output = .object(fields) }
        else { output = .object(["http_status":.number(Double(result.status)),"result":output]) }
        return output
    }
    public func secretPlanArguments(scope: RepositoryScope, name: String, environment: String?, dependabot: Bool, value: Data) async throws -> (String,JSON) {
        guard !name.isEmpty, name.count <= 100, !name.hasPrefix("GITHUB_"), name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_").contains($0) }) else { throw RMError.invalidInput }
        _ = try await verify(scope,permission:"admin")
        let type = dependabot ? "dependabot" : "actions"
        let encodedEnvironment = try environment.map { try URLPolicy.encodedSegment(InputValidation.entitySegment($0)) }
        let prefix = encodedEnvironment.map { repo(scope)+"/environments/\($0)/secrets" } ?? repo(scope)+"/\(type)/secrets"
        let key = try await get(scope,path:prefix+"/public-key")
        guard let encoded = key["key"].string, let id = key["key_id"].string else { throw RMError.upstream }
        let encrypted = try SecretEncryption.sealedBox(value,publicKeyBase64:encoded)
        var args: [String:JSON] = ["name":.string(name),"body":.object(["encrypted_value":.string(encrypted),"key_id":.string(id)])]
        if let environment { args["environment"] = .string(environment) }
        return (environment != nil ? "set_environment_secret" : dependabot ? "set_dependabot_secret" : "set_secret", .object(args))
    }
    public func reconcile(_ receipt:MutationReceipt) async throws -> JSON {
        let token = try await connections.token(for:receipt.scope)
        let path = receipt.scope.repositoryID == 0 ? repo(receipt.scope) : "repositories/\(receipt.scope.repositoryID)"
        var observed: [String:JSON] = ["operation":.string(receipt.operation),"state":"uncertain",
            "reviewed_arguments":receipt.reviewedArguments ?? .null,"reviewed_before":receipt.reviewedBefore ?? .null]
        do {
            let info = try await request(path:path,token:token).json
            observed["repository"] = info
            guard let fullName = info["full_name"].string,let id = info["id"].int else { throw RMError.upstream }
            let parts = fullName.split(separator:"/").map(String.init)
            guard parts.count == 2 else { throw RMError.upstream }
            let scope = RepositoryScope(accountID:receipt.scope.accountID,connectionID:receipt.scope.connectionID,
                repositoryID:Int64(id),owner:parts[0],name:parts[1],branch:receipt.scope.branch)
            if receipt.operation == "commit" {
                observed["head"] = .string(try await head(scope)); observed["reviewed_head"] = receipt.expectedHead.map(JSON.string) ?? .null
            } else if receipt.operation != "create_repository",let arguments = receipt.reviewedArguments {
                do { observed["target"] = try await remoteSnapshot(ToolCatalog.named(receipt.operation),arguments:arguments,scope:scope) }
                catch { observed["target_status"] = "Unavailable; outcome cannot be established automatically." }
            }
        } catch RMError.unavailable {
            observed["repository_status"] = "Not visible to this account. Deletion, transfer and revoked access cannot be distinguished."
        } catch RMError.forbidden {
            observed["repository_status"] = "Access denied. Outcome remains unknown."
        }
        observed["notice"] = "Inspect the target and GitHub activity before acknowledging the outcome. This inspection never retries a write."
        return GitHubRedaction.clean(.object(observed))
    }
    func publish(_ plan: MutationPlan, message: String, validate: @escaping @Sendable () async throws -> Void) async throws -> JSON {
        guard let draft = plan.draft, !draft.changes.isEmpty || plan.arguments["merge_parent"].string != nil else { throw RMError.invalidInput }
        let scope = draft.scope; let token = try await connections.token(for:scope)
        try await validate(); guard try await head(scope) == plan.expectedHead else { throw RMError.conflict }
        let base = try await get(scope,path:repo(scope)+"/git/commits/\(plan.expectedHead)")
        var entries: [JSON] = []
        for change in draft.changes {
            try await validate(); _ = try InputValidation.path(change.path)
            guard ["100644","100755"].contains(change.mode) else { throw RMError.unsupported }
            var entry: [String:JSON] = ["path":.string(change.path),"type":"blob","mode":.string(change.mode),"sha":.null]
            if let data = change.updated {
                if let text = String(data:data,encoding:.utf8), !RepositorySecretScanner.scan(text).findings.isEmpty { throw RMError.forbidden }
                let blob = try await request(path:repo(scope)+"/git/blobs",token:token,method:"POST",body:.object(["content":.string(data.base64EncodedString()),"encoding":"base64"]))
                guard let sha = blob.json["sha"].string else { throw RMError.upstream }; entry["sha"] = .string(try InputValidation.sha(sha))
            }
            entries.append(.object(entry))
        }
        try await validate()
        let tree = try await request(path:repo(scope)+"/git/trees",token:token,method:"POST",body:.object(["base_tree":base["tree"]["sha"],"tree":.array(entries)]))
        guard let treeSHA = tree.json["sha"].string else { throw RMError.upstream }
        var parents: [JSON] = [.string(plan.expectedHead)]
        if let mergeParent = plan.arguments["merge_parent"].string { parents.append(.string(try InputValidation.sha(mergeParent))) }
        try await validate()
        let commit = try await request(path:repo(scope)+"/git/commits",token:token,method:"POST",body:.object(["message":.string(message),"tree":.string(treeSHA),"parents":.array(parents)]))
        guard let sha = commit.json["sha"].string else { throw RMError.upstream }
        try await validate(); guard try await head(scope) == plan.expectedHead else { throw RMError.conflict }
        try await validate()
        _ = try await request(path:repo(scope)+"/git/refs/heads/\(scope.branch)",token:token,method:"PATCH",body:.object(["sha":.string(sha),"force":false]))
        guard try await head(scope) == sha else { throw RMError.uncertainWrite }
        return .object(["sha":.string(sha),"parents":.array(parents),"repository":.string(scope.fullName)])
    }
    func request(path: String, token: String, method: String = "GET", body: JSON = .null, query: [String:String] = [:],write:Bool? = nil) async throws -> HTTPResult {
        let segments = try path.split(separator:"/").map { part -> String in guard let value = String(part).removingPercentEncoding else { throw RMError.invalidInput }; return value }
        let url = try URLPolicy.append(URL(string:"https://api.github.com")!,segments:segments,query:query)
        var request = URLRequest(url:url); request.httpMethod = method
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization"); request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("2026-03-10",forHTTPHeaderField:"X-GitHub-Api-Version")
        if body != .null { request.httpBody = body.encoded; request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        let isWrite = write ?? (method != "GET")
        do {
            let result = try await transport.send(request,limit:8*1024*1024)
            if isWrite && (result.status >= 500 || result.status == 408) { throw RMError.uncertainWrite }
            try SecureHTTPTransport.checkStatus(result.status)
            if isWrite && result.data.isEmpty && ![202,204].contains(result.status) { throw RMError.uncertainWrite }
            if isWrite && !result.data.isEmpty && (try? JSON.parse(result.data)) == nil { throw RMError.uncertainWrite }
            return result
        }
        catch let e as RMError {
            if isWrite && [RMError.connection,.cancelled,.tooLarge].contains(e) { throw RMError.uncertainWrite }; throw e
        }
    }
    public func repo(_ scope: RepositoryScope) -> String { "repos/\(scope.owner)/\(scope.name)" }
    public func expanded(_ template: String, arguments: JSON, scope: RepositoryScope) throws -> String {
        var path = template.replacingOccurrences(of:"{owner}",with:scope.owner).replacingOccurrences(of:"{repo}",with:scope.name)
        for key in ["id","review_id","branch","tag","sha","base","head","label","username","environment","name"] where path.contains("{\(key)}") {
            let value = arguments[key].string ?? arguments[key].int.map(String.init)
            guard let value else { throw RMError.invalidInput }
            if ["branch","tag","base","head"].contains(key) { _ = try InputValidation.ref(value) }
            else if key == "sha" { _ = try InputValidation.sha(value) }
            else if ["label","environment"].contains(key) { _ = try InputValidation.entitySegment(value) }
            else { _ = try InputValidation.component(value) }
            path = path.replacingOccurrences(of:"{\(key)}",with:try URLPolicy.encodedSegment(value))
        }
        guard !path.contains("{"), !path.contains("}"), !path.contains("..") else { throw RMError.invalidInput }
        return path
    }
}
public enum GitHubRedaction {
    public static func clean(_ value: JSON) -> JSON {
        switch value {
        case .string(let t): return .string(RepositorySecretScanner.scan(t).redacted)
        case .array(let a): return .array(a.map(clean))
        case .object(let o): return .object(o.mapValues { clean($0) }.filter { !["secret","token","access_token","refresh_token","encrypted_value","private_key"].contains($0.key.lowercased()) })
        default: return value
        }
    }
}
