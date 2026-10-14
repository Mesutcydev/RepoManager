import Foundation

extension GitHubClient {
    private func graph(_ query: String, variables: [String: JSON], scope: RepositoryScope, validate:(@Sendable () async throws -> Void)? = nil) async throws -> JSON {
        let token = try await connections.token(for:scope)
        try await validate?()
        let result = try await request(path:"graphql",token:token,method:"POST",
            body:.object(["query":.string(query),"variables":.object(variables)]),write:validate != nil)
        guard let root = try? JSON.parse(result.data) else { throw validate == nil ? RMError.upstream : RMError.uncertainWrite }
        guard root["errors"] == .null else { throw validate == nil ? RMError.forbidden : RMError.uncertainWrite }
        if validate != nil && root["data"].object == nil { throw RMError.uncertainWrite }; return root["data"]
    }
    private var repositorySelection: String { "id databaseId nameWithOwner" }
    func graphRead(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope) async throws -> JSON {
        var variables: [String:JSON] = ["owner":.string(scope.owner),"name":.string(scope.name)]
        let selection: String
        switch definition.name {
        case "list_discussions": selection = "discussionCategories(first:30){nodes{id name}} discussions(first:30){nodes{id number title body updatedAt url}}"
        case "discussion_comments":
            variables["number"] = arguments["number"]
            selection = "discussion(number:$number){id number title body comments(first:30){nodes{id body author{login} replies(first:20){nodes{id body}}}}}"
        case "review_threads":
            variables["number"] = arguments["number"]
            selection = "pullRequest(number:$number){id number headRefOid isDraft reviewThreads(first:30){nodes{id isResolved path line comments(first:20){nodes{id body}}}}}"
        case "linked_projects": selection = "projectsV2(first:20){nodes{id title fields(first:30){nodes{... on ProjectV2Field{id name dataType} ... on ProjectV2SingleSelectField{id name options{id name}}}} items(first:100){nodes{id content{... on Issue{id number title repository{databaseId}} ... on PullRequest{id number title repository{databaseId}}}}}}}"
        default: throw RMError.unsupported
        }
        let numberParam = variables["number"] == nil ? "" : ", $number:Int!"
        var data = try await graph("query($owner:String!,$name:String!\(numberParam)){repository(owner:$owner,name:$name){\(repositorySelection) \(selection)}}",variables:variables,scope:scope)
        guard data["repository"]["databaseId"].int == Int(scope.repositoryID) else { throw RMError.forbidden }
        if definition.name == "linked_projects", let projects = data["repository"]["projectsV2"]["nodes"].array {
            let filtered = projects.map { p -> JSON in
                var p = p.object ?? [:]; var items = p["items"]?.object ?? [:]
                items["nodes"] = .array(items["nodes"]?.array?.filter { $0["content"]["repository"]["databaseId"].int == Int(scope.repositoryID) } ?? [])
                p["items"] = .object(items); return .object(p)
            }
            var repo = data["repository"].object ?? [:]; repo["projectsV2"] = .object(["nodes":.array(filtered)])
            data = .object(["repository":.object(repo)])
        }
        return GitHubRedaction.clean(data)
    }
    func graphMutationSnapshot(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope) async throws -> JSON {
        let repo = try await verify(scope,permission:definition.permission)
        if definition.name == "ready_pull_request" {
            return try await get(scope,path:self.repo(scope)+"/pulls/\(arguments["number"].int ?? 0)")
        }
        if ["add_project_item","update_project_item"].contains(definition.name) {
            let projects = try await graphRead(ToolCatalog.named("linked_projects"),arguments:.object([:]),scope:scope)
            guard let project = projects["repository"]["projectsV2"]["nodes"].array?.first(where:{ $0["id"] == arguments["project_id"] }) else { throw RMError.forbidden }
            if definition.name == "update_project_item" {
                guard project["items"]["nodes"].array?.contains(where: { $0["id"] == arguments["item_id"] }) == true,
                      project["fields"]["nodes"].array?.contains(where: { $0["id"] == arguments["field_id"] }) == true else { throw RMError.forbidden }
            } else {
                _ = try await scopedNode(arguments["content_id"],scope:scope)
            }
            return project
        }
        if definition.name == "create_discussion" {
            let categories = try await graphRead(ToolCatalog.named("list_discussions"),arguments:.object([:]),scope:scope)
            guard categories["repository"]["discussionCategories"]["nodes"].array?.contains(where:{ $0["id"] == arguments["category_id"] }) == true else { throw RMError.forbidden }
            return categories
        }
        let node = arguments["discussion_id"] != .null ? arguments["discussion_id"] : arguments["thread_id"]
        if node != .null { return try await scopedNode(node,scope:scope) }
        return repo
    }
    private func scopedNode(_ id: JSON, scope: RepositoryScope) async throws -> JSON {
        guard let value = id.string, !value.isEmpty, value.count <= 200 else { throw RMError.invalidInput }
        let query = "query($id:ID!){node(id:$id){... on Issue{id number updatedAt repository{databaseId}} ... on PullRequest{id number updatedAt headRefOid repository{databaseId}} ... on Discussion{id number updatedAt repository{databaseId}} ... on PullRequestReviewThread{id isResolved pullRequest{headRefOid repository{databaseId}} comments(first:30){nodes{id body}}}}}"
        let data = try await graph(query,variables:["id":id],scope:scope)["node"]
        let repositoryID = data["repository"]["databaseId"].int ?? data["pullRequest"]["repository"]["databaseId"].int
        guard repositoryID == Int(scope.repositoryID) else { throw RMError.forbidden }; return data
    }
    func graphMutate(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope, validate:@escaping @Sendable () async throws -> Void) async throws -> JSON {
        _ = try await graphMutationSnapshot(definition,arguments:arguments,scope:scope)
        var input: [String:JSON] = [:]; let operation = definition.path
        let type: String; let result: String
        switch definition.name {
        case "create_discussion":
            let repo = try await verify(scope,permission:"push")
            input = ["repositoryId":repo["node_id"],"categoryId":arguments["category_id"],"title":arguments["title"],"body":arguments["body"]]
            type = "CreateDiscussionInput"; result = "discussion{id number}"
        case "comment_discussion": input = ["discussionId":arguments["discussion_id"],"body":arguments["body"]]; type = "AddDiscussionCommentInput"; result = "comment{id}"
        case "resolve_thread": input = ["threadId":arguments["thread_id"]]; type = "ResolveReviewThreadInput"; result = "thread{id isResolved}"
        case "ready_pull_request":
            let pr = try await get(scope,path:repo(scope)+"/pulls/\(arguments["number"].int ?? 0)")
            input = ["pullRequestId":pr["node_id"]]; type = "MarkPullRequestReadyForReviewInput"; result = "pullRequest{id isDraft}"
        case "add_project_item": input = ["projectId":arguments["project_id"],"contentId":arguments["content_id"]]; type = "AddProjectV2ItemByIdInput"; result = "item{id}"
        case "update_project_item":
            var values: [String:JSON] = [:]
            for (from,to) in [("text","text"),("number","number"),("date","date"),("single_select_option_id","singleSelectOptionId")] where arguments[from] != .null { values[to] = arguments[from] }
            guard values.count == 1 else { throw RMError.invalidInput }
            input = ["projectId":arguments["project_id"],"itemId":arguments["item_id"],"fieldId":arguments["field_id"],"value":.object(values)]
            type = "UpdateProjectV2ItemFieldValueInput"; result = "projectV2Item{id}"
        default: throw RMError.unsupported
        }
        return GitHubRedaction.clean(try await graph("mutation($input:\(type)!){\(operation)(input:$input){\(result)}}",variables:["input":.object(input)],scope:scope,validate:validate))
    }
}
