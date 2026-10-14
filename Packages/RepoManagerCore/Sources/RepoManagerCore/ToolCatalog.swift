import Foundation

public struct ToolDefinition: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String; public var group: String; public var description: String
    public var risk: Risk; public var permission: String
    public var method: String; public var path: String; public var reviewPath: String?
    public var schema: JSON; public var nativeOnly: Bool
    public init(name: String, group: String, description: String, risk: Risk = .read, permission: String = "pull",
                method: String = "GET", path: String = "", reviewPath: String? = nil, schema: JSON, nativeOnly: Bool = false) {
        self.name = name; self.group = group; self.description = description
        self.risk = method == "DELETE" && risk != .destructive ? .consequential : risk; self.permission = permission
        self.method = method; self.path = path; self.reviewPath = reviewPath; self.schema = schema; self.nativeOnly = nativeOnly
    }
}
public enum Schema {
    public static func string(_ max: Int = 4096) -> JSON { .object(["type": "string", "maxLength": .number(Double(max))]) }
    public static var integer: JSON { .object(["type": "integer", "minimum": 1, "maximum": 2147483647]) }
    public static var boolean: JSON { .object(["type": "boolean"]) }
    public static func choices(_ values: [String]) -> JSON { .object(["type": "string", "enum": .array(values.map(JSON.string))]) }
    public static func array(_ value: JSON) -> JSON { .object(["type": "array", "items": value, "maxItems": 100]) }
    public static func object(_ fields: [String: JSON], required: [String] = []) -> JSON {
        .object(["type": "object", "properties": .object(fields), "required": .array(required.map(JSON.string)), "additionalProperties": false])
    }
    public static func validate(_ value: JSON, against schema: JSON, depth: Int = 0) throws {
        guard depth < 12, value.encoded.count <= 2 * 1024 * 1024 else { throw RMError.tooLarge }
        if let choices = schema["enum"].array, !choices.contains(value) { throw RMError.invalidInput }
        switch schema["type"].string {
        case "object":
            guard let object = value.object else { throw RMError.invalidInput }
            let fields = schema["properties"].object ?? [:]
            if schema["additionalProperties"].bool == false && !Set(object.keys).isSubset(of: Set(fields.keys)) { throw RMError.invalidInput }
            for key in schema["required"].array?.compactMap(\.string) ?? [] where object[key] == nil { throw RMError.invalidInput }
            guard object.count <= 100 else { throw RMError.tooLarge }
            for (key, val) in object {
                if let rule = fields[key] { try validate(val, against: rule, depth: depth+1) }
                else {
                    guard schema["additionalProperties"].bool == true, key.utf8.count <= 200 else { throw RMError.invalidInput }
                    switch val { case .string(let text): guard text.utf8.count <= 4096, !text.contains("\0") else { throw RMError.invalidInput }; case .number(let n): guard n.isFinite else { throw RMError.invalidInput }; case .bool: break; default: throw RMError.invalidInput }
                }
            }
        case "string": guard let text = value.string, text.count <= (schema["maxLength"].int ?? 4096), !text.contains("\0") else { throw RMError.invalidInput }
        case "integer": guard let n = value.int, n >= (schema["minimum"].int ?? Int.min), n <= (schema["maximum"].int ?? Int.max) else { throw RMError.invalidInput }
        case "number": guard case .number(let n) = value, n.isFinite else { throw RMError.invalidInput }
        case "boolean": guard value.bool != nil else { throw RMError.invalidInput }
        case "array":
            guard let list = value.array, list.count <= (schema["maxItems"].int ?? 100) else { throw RMError.invalidInput }
            for val in list { try validate(val, against: schema["items"], depth: depth+1) }
        default: throw RMError.invalidInput
        }
    }
}
public enum ToolCatalog {
    public static var all: [ToolDefinition] { local + remote + collaboration + utilities + extended }
    public static var extended: [ToolDefinition] {
        let r = "repos/{owner}/{repo}", id = Schema.integer, s = Schema.string(200)
        let rules = Schema.object(["type":Schema.choices(["creation","update","deletion","required_linear_history","required_signatures","non_fast_forward","pull_request","required_status_checks","required_deployments"]),
            "parameters":Schema.object(["required_approving_review_count":.object(["type":"integer","minimum":0,"maximum":6]),"dismiss_stale_reviews_on_push":Schema.boolean,"require_code_owner_review":Schema.boolean,"require_last_push_approval":Schema.boolean,"required_review_thread_resolution":Schema.boolean,"strict_required_status_checks_policy":Schema.boolean,"required_status_checks":Schema.array(Schema.object(["context":s,"integration_id":id],required:["context"])),"required_deployment_environments":Schema.array(s)])],required:["type"])
        let body: [String:JSON] = ["name":s,"target":Schema.choices(["branch","tag"]),"enforcement":Schema.choices(["disabled","active","evaluate"]),"conditions":Schema.object(["ref_name":Schema.object(["include":Schema.array(s),"exclude":Schema.array(s)],required:["include","exclude"])]),"rules":Schema.array(rules),"bypass_actors":Schema.array(Schema.object(["actor_id":id,"actor_type":Schema.choices(["Integration","OrganizationAdmin","RepositoryRole","Team"]),"bypass_mode":Schema.choices(["always","pull_request"])],required:["actor_type","bypass_mode"]))]
        return [
            rest("create_ruleset","Administration",r+"/rulesets","POST",.consequential,body:body,bodyRequired:["name","target","enforcement","rules"],permission:"admin",review:r+"/rulesets"),
            rest("update_ruleset","Administration",r+"/rulesets/{id}","PUT",.consequential,fields:["id":id],required:["id"],body:body,permission:"admin",review:r+"/rulesets/{id}"),
            rest("set_branch_protection","Administration",r+"/branches/{branch}/protection","PUT",.consequential,fields:["branch":s],required:["branch"],body:["required_status_checks":Schema.object(["strict":Schema.boolean,"contexts":Schema.array(s)],required:["strict","contexts"]),"enforce_admins":Schema.boolean,"required_pull_request_reviews":Schema.object(["dismiss_stale_reviews":Schema.boolean,"require_code_owner_reviews":Schema.boolean,"required_approving_review_count":.object(["type":"integer","minimum":0,"maximum":6])]),"restrictions":Schema.object(["users":Schema.array(s),"teams":Schema.array(s),"apps":Schema.array(s)]),"required_linear_history":Schema.boolean,"allow_force_pushes":Schema.boolean,"allow_deletions":Schema.boolean,"required_conversation_resolution":Schema.boolean,"lock_branch":Schema.boolean],bodyRequired:["required_status_checks","enforce_admins","required_pull_request_reviews","restrictions"],permission:"admin",review:r+"/branches/{branch}"),
            rest("update_webhook","Administration",r+"/hooks/{id}","PATCH",.consequential,fields:["id":id],required:["id"],body:["active":Schema.boolean,"events":Schema.array(s),"config":Schema.object(["url":Schema.string(2048),"content_type":Schema.choices(["json","form"]),"insecure_ssl":Schema.choices(["0"])])],permission:"admin",review:r+"/hooks/{id}"),
            ToolDefinition(name:"download_artifact",group:"Actions",description:"Download a selected artifact into encrypted 1-MiB chunks; maximum 50 MiB.",path:"asset-download",schema:Schema.object(["id":id],required:["id"])),
            ToolDefinition(name:"upload_release_asset",group:"Releases",description:"Upload an explicitly imported encrypted asset after native review.",risk:.mutation,permission:"push",method:"ASSET",path:r+"/releases/{id}/assets",reviewPath:r+"/releases/{id}",schema:Schema.object(["id":id,"asset_id":Schema.string(64)],required:["id","asset_id"]))
        ]
    }
    public static func named(_ name: String) throws -> ToolDefinition {
        guard let d = all.first(where: { $0.name == name }) else { throw RMError.unsupported }; return d
    }
    private static func localTool(_ name: String, _ description: String, fields: [String: JSON] = [:], required: [String] = [], edit: Bool = false) -> ToolDefinition {
        ToolDefinition(name: name, group: "Workspace", description: description, risk: edit ? .localEdit : .read,
                       permission: edit ? "push" : "pull", schema: Schema.object(fields, required: required))
    }
    public static var local: [ToolDefinition] {
        let p = Schema.string(1024), t = Schema.string(262144)
        return [
            localTool("list_files", "List the selected branch tree and staged overlay. Bounded coverage.", fields: ["path": p]),
            localTool("read_file", "Read text on the selected commit with credentials masked.", fields: ["path": p], required: ["path"]),
            localTool("read_file_range", "Read up to 200 lines.", fields: ["path": p, "start": Schema.integer, "count": .object(["type":"integer","minimum":1,"maximum":200])], required:["path","start"]),
            localTool("write_file", "Stage text locally. No remote writes.", fields:["path":p,"content":t], required:["path","content"], edit:true),
            localTool("replace_text", "Stage exactly one matching text replacement.", fields:["path":p,"find":t,"replace":t], required:["path","find","replace"], edit:true),
            localTool("delete_file", "Stage a file deletion locally.", fields:["path":p], required:["path"], edit:true),
            localTool("move_file", "Stage an atomic move preserving mode.", fields:["path":p,"destination":p], required:["path","destination"], edit:true),
            localTool("upload_attachment", "Stage explicitly attached bytes as an opaque repository asset; maximum 1 MiB.", fields:["attachment_id":Schema.string(64),"path":p], required:["attachment_id","path"], edit:true),
            localTool("apply_patch", "Validate and stage a unified patch; no fuzzy matching.", fields:["patch":Schema.string(1024*1024)], required:["patch"], edit:true),
            localTool("select_hunks", "Keep selected hunk indexes from the current draft file.", fields:["path":p,"hunks":Schema.array(.object(["type":"integer","minimum":0,"maximum":999]))], required:["path","hunks"], edit:true),
            localTool("git_diff", "Show the staged before/after comparison with masked credentials."),
            localTool("search_branch", "Lexically search up to 20 text files on the selected branch.", fields:["query":Schema.string(300)], required:["query"]),
            localTool("repository_context_map", "Summarize paths and declarations in a bounded selected-branch map."),
            localTool("scan_secrets", "Scan up to 20 paths; return names, kinds, lines and coverage only.", fields:["paths":Schema.array(p)]),
            localTool("redact_secrets", "Stage detected credential redaction; original values remain private.", fields:["path":p], required:["path"], edit:true),
            localTool("audit_secret_history", "Audit up to five paths and ten commits each, displaying coverage.", fields:["paths":Schema.array(p)], required:["paths"]),
            localTool("checkpoint", "Create a local draft checkpoint.", fields:["title":Schema.string(200)], required:["title"], edit:true),
            localTool("restore_checkpoint", "Restore a local checkpoint; invalidate prior reviews.", fields:["id":Schema.string(64)], required:["id"], edit:true),
            localTool("request_user_approval", "Prepare an immutable commit review. Publication remains native-only.", fields:["message":Schema.string(1000)], required:["message"]),
            localTool("revert_last_commit", "Prepare a forward revert of a single-parent commit; no history rewrite.", fields:["message":Schema.string(1000)], required:["message"], edit:true),
            localTool("merge_branch", "Prepare a clean two-parent merge or bounded conflict review.", fields:["head":Schema.string(200)], required:["head"], edit:true)
        ]
    }
    private static func rest(_ name: String, _ group: String, _ path: String, _ method: String = "GET", _ risk: Risk = .read,
                             fields: [String: JSON] = [:], required: [String] = [], body: [String: JSON]? = nil, bodyRequired: [String] = [],
                             permission: String? = nil, review: String? = nil, native: Bool = false) -> ToolDefinition {
        var params = fields
        if let body { params["body"] = Schema.object(body, required: bodyRequired) }
        var required = required; if body != nil && method != "GET" { required.append("body") }
        return ToolDefinition(name: name, group: group, description: about[name] ?? name.replacingOccurrences(of:"_",with:" ").capitalized + ".",
            risk: risk, permission: permission ?? (risk == .read ? "pull" : "push"), method: method, path: path,
            reviewPath: review, schema: Schema.object(params, required: required), nativeOnly: native)
    }
    /// One plain sentence per REST tool. People read these in Tools and models receive them with every
    /// request, so they stay short and name the arguments that matter. Scope and review rules live in the system prompt.
    static let about: [String:String] = [
        "repository_info": "Read the repository's details: default branch, visibility, topics, and counts.",
        "list_branches": "List the repository's branches and their head commits.",
        "list_tags": "List the repository's tags and their commits.",
        "git_log": "List recent commits on the selected branch, optionally only those that touch a path.",
        "compare_commits": "Compare base and head refs: commits ahead and behind, and changed files with patches.",
        "search_code": "Search this repository's code by keywords, without qualifiers. GitHub indexes only the default branch.",
        "activity": "List recent repository events such as pushes, pull requests, issues, and releases.",
        "create_branch": "Create a branch at a commit SHA. Pass ref as refs/heads/<name>.",
        "delete_branch": "Delete a branch by name.",
        "create_tag": "Create a lightweight tag at a commit SHA. Pass ref as refs/tags/<name>.",
        "delete_tag": "Delete a tag by name.",
        "list_issues": "List issues by state: open, closed, or all. GitHub includes pull requests in this list.",
        "search_issues": "Search this repository's issues by keywords, without qualifiers.",
        "read_issue": "Read one issue by number: title, body, state, labels, and assignees.",
        "create_issue": "Open an issue with a title and optional body, labels, assignees, and milestone.",
        "edit_issue": "Change an issue's title, body, state, labels, assignees, or milestone.",
        "issue_comments": "Read the comments on an issue or pull request by number.",
        "comment_issue": "Add a comment to an issue or pull request by number.",
        "edit_issue_comment": "Replace the text of an issue comment by comment ID.",
        "delete_issue_comment": "Delete an issue comment by comment ID.",
        "list_labels": "List the repository's labels with colors and descriptions.",
        "create_label": "Create a label with a name, hex color, and optional description.",
        "edit_label": "Rename a label or change its color or description.",
        "delete_label": "Delete a label and remove it from every issue and pull request.",
        "list_milestones": "List milestones with due dates and open and closed issue counts.",
        "create_milestone": "Create a milestone with a title and optional description and due date.",
        "edit_milestone": "Change a milestone's title, description, due date, or state.",
        "delete_milestone": "Delete a milestone. Its issues remain and lose the milestone.",
        "list_pull_requests": "List pull requests by state: open, closed, or all.",
        "search_pull_requests": "Search this repository's pull requests by keywords, without qualifiers.",
        "read_pull_request": "Read one pull request: description, branches, mergeability, and review state.",
        "pull_request_files": "List a pull request's changed files with additions, deletions, and patches.",
        "open_pull_request": "Open a pull request from head into base with a title and description, optionally as a draft.",
        "update_pull_request": "Change a pull request's title, description, base branch, draft status, or state.",
        "pull_request_reviews": "List the reviews submitted on a pull request.",
        "draft_review": "Start a pending pull request review with a summary and line comments.",
        "submit_review": "Submit a pending review as APPROVE, REQUEST_CHANGES, or COMMENT.",
        "inline_comment": "Comment on lines of a pull request diff, or reply to an existing review comment.",
        "request_reviewers": "Ask users or teams to review a pull request.",
        "merge_pull_request": "Merge a pull request by merge, squash, or rebase. The head SHA must still match.",
        "workflow_status": "List recent workflow runs on the selected branch with status and conclusion.",
        "list_workflows": "List the repository's workflows and whether each is active.",
        "read_workflow_run": "Read one workflow run: trigger, commit, status, conclusion, and timing.",
        "workflow_jobs": "List a workflow run's jobs and steps with status and conclusion.",
        "workflow_logs": "Read the first 64 KiB of a job's log, with credentials masked.",
        "check_run_status": "List the check runs for a commit SHA with status and conclusion.",
        "dispatch_workflow": "Start a workflow that has a workflow_dispatch trigger on a ref, with optional inputs.",
        "rerun_workflow": "Re-run every job in a workflow run.",
        "cancel_workflow": "Cancel a queued or running workflow run.",
        "list_artifacts": "List the repository's build artifacts with size and expiry.",
        "artifact_metadata": "Read one artifact's name, size, expiry, and the run that produced it.",
        "delete_artifact": "Delete a build artifact by ID.",
        "pending_deployments": "List the deployments in a run that are waiting for environment approval.",
        "approve_deployment": "Approve or reject waiting deployments to the given environments, with a comment.",
        "list_releases": "List releases and pre-releases with their tags.",
        "read_release": "Read one release: tag, notes, assets, and draft or pre-release state.",
        "create_release": "Create a release for a tag with written or generated notes, optionally as a draft or pre-release.",
        "edit_release": "Change a release's tag, title, notes, or draft, pre-release, and latest status.",
        "delete_release": "Delete a release. Its Git tag is kept.",
        "release_assets": "List the files attached to a release.",
        "delete_release_asset": "Delete one file attached to a release.",
        "dependabot_alerts": "List Dependabot alerts for vulnerable dependencies.",
        "code_scanning_alerts": "List code scanning alerts with rule, severity, and location.",
        "secret_scanning_alerts": "List secret scanning alerts by type and state. Secret values are never returned.",
        "update_dependabot_alert": "Dismiss a Dependabot alert with a reason, or reopen it.",
        "update_code_scanning_alert": "Dismiss a code scanning alert with a reason, or reopen it.",
        "update_secret_scanning_alert": "Resolve a secret scanning alert with a resolution, or reopen it.",
        "create_repository": "Create a repository on your account with a name, visibility, and optional README, .gitignore, and license.",
        "fork_repository": "Fork this repository to your account or an organization.",
        "repository_settings": "Change the name, description, visibility, default branch, features, or merge options.",
        "collaborators": "List collaborators and their permission levels.",
        "set_collaborator": "Invite a user or change their permission: pull, triage, push, maintain, or admin.",
        "remove_collaborator": "Remove a collaborator's access to the repository.",
        "list_environments": "List deployment environments and their protection rules.",
        "set_environment": "Create or update an environment's wait timer, required reviewers, and self-review rule.",
        "delete_environment": "Delete a deployment environment, including its secrets and protection rules.",
        "list_webhooks": "List webhooks with their events and delivery URLs.",
        "create_webhook": "Add a webhook that posts selected events to an HTTPS URL.",
        "update_webhook": "Change a webhook's URL, events, or active state.",
        "delete_webhook": "Delete a webhook.",
        "list_rulesets": "List the repository's branch and tag rulesets.",
        "create_ruleset": "Create a branch or tag ruleset with targets, rules, enforcement, and bypass actors.",
        "update_ruleset": "Replace a ruleset's targets, rules, enforcement, or bypass actors.",
        "delete_ruleset": "Delete a ruleset.",
        "branch_protection": "Read a branch's protection: required reviews, status checks, and restrictions.",
        "set_branch_protection": "Set a branch's required reviews and checks, push restrictions, and force-push and deletion rules.",
        "delete_branch_protection": "Remove all protection from a branch.",
        "transfer_repository": "Transfer this repository to another user or organization.",
        "delete_repository": "Permanently delete this repository with its issues, pull requests, and releases.",
        "list_secrets": "List Actions secret names and update dates. Values are never readable.",
        "list_dependabot_secrets": "List Dependabot secret names and update dates. Values are never readable.",
        "list_environment_secrets": "List an environment's secret names and update dates. Values are never readable.",
        "set_secret": "Create or replace an Actions secret from a value entered in the app.",
        "set_dependabot_secret": "Create or replace a Dependabot secret from a value entered in the app.",
        "set_environment_secret": "Create or replace an environment secret from a value entered in the app.",
        "delete_secret": "Delete an Actions secret by name.",
        "delete_dependabot_secret": "Delete a Dependabot secret by name.",
        "delete_environment_secret": "Delete an environment secret by name."
    ]
    public static var remote: [ToolDefinition] {
        let r = "repos/{owner}/{repo}", s = Schema.string(), short = Schema.string(200), id = Schema.integer
        let issue: [String:JSON] = ["title":s,"body":Schema.string(65536),"state":Schema.choices(["open","closed"]),"labels":Schema.array(short),"assignees":Schema.array(short),"milestone":id]
        let pr: [String:JSON] = ["title":s,"body":Schema.string(65536),"state":Schema.choices(["open","closed"]),"base":short,"head":short,"draft":Schema.boolean,"maintainer_can_modify":Schema.boolean]
        let release: [String:JSON] = ["tag_name":short,"target_commitish":short,"name":s,"body":Schema.string(65536),"draft":Schema.boolean,"prerelease":Schema.boolean,"generate_release_notes":Schema.boolean,"make_latest":Schema.choices(["true","false","legacy"])]
        let n = ["id":id]
        return [
            rest("repository_info","Repositories",r), rest("list_branches","Repositories",r+"/branches"), rest("list_tags","Repositories",r+"/tags"),
            rest("git_log","Repositories",r+"/commits",fields:["path":Schema.string(1024)]),
            rest("compare_commits","Repositories",r+"/compare/{base}...{head}",fields:["base":short,"head":short],required:["base","head"]),
            rest("search_code","Repositories","search/code",fields:["query":Schema.string(300)],required:["query"]),
            rest("activity","Activity",r+"/events"),
            rest("create_branch","Changes",r+"/git/refs","POST",.mutation,body:["ref":short,"sha":Schema.string(64)],bodyRequired:["ref","sha"],review:r+"/git/matching-refs/heads"),
            rest("delete_branch","Changes",r+"/git/refs/heads/{branch}","DELETE",.consequential,fields:["branch":short],required:["branch"],review:r+"/git/ref/heads/{branch}"),
            rest("create_tag","Changes",r+"/git/refs","POST",.mutation,body:["ref":short,"sha":Schema.string(64)],bodyRequired:["ref","sha"],review:r+"/git/matching-refs/tags"),
            rest("delete_tag","Changes",r+"/git/refs/tags/{tag}","DELETE",.consequential,fields:["tag":short],required:["tag"],review:r+"/git/ref/tags/{tag}"),
            rest("list_issues","Issues",r+"/issues",fields:["state":Schema.choices(["open","closed","all"])]),
            rest("search_issues","Issues","search/issues",fields:["query":Schema.string(300)],required:["query"]),
            rest("read_issue","Issues",r+"/issues/{id}",fields:n,required:["id"]),
            rest("create_issue","Issues",r+"/issues","POST",.mutation,body:issue,bodyRequired:["title"],review:r+"/issues"),
            rest("edit_issue","Issues",r+"/issues/{id}","PATCH",.mutation,fields:n,required:["id"],body:issue,review:r+"/issues/{id}"),
            rest("issue_comments","Issues",r+"/issues/{id}/comments",fields:n,required:["id"]),
            rest("comment_issue","Issues",r+"/issues/{id}/comments","POST",.mutation,fields:n,required:["id"],body:["body":Schema.string(65536)],bodyRequired:["body"],review:r+"/issues/{id}/comments"),
            rest("edit_issue_comment","Issues",r+"/issues/comments/{id}","PATCH",.mutation,fields:n,required:["id"],body:["body":Schema.string(65536)],bodyRequired:["body"],review:r+"/issues/comments/{id}"),
            rest("delete_issue_comment","Issues",r+"/issues/comments/{id}","DELETE",.mutation,fields:n,required:["id"],review:r+"/issues/comments/{id}"),
            rest("list_labels","Issues",r+"/labels"),
            rest("create_label","Issues",r+"/labels","POST",.mutation,body:["name":short,"color":Schema.string(6),"description":s],bodyRequired:["name","color"],review:r+"/labels"),
            rest("edit_label","Issues",r+"/labels/{label}","PATCH",.mutation,fields:["label":short],required:["label"],body:["new_name":short,"color":Schema.string(6),"description":s],review:r+"/labels/{label}"),
            rest("delete_label","Issues",r+"/labels/{label}","DELETE",.mutation,fields:["label":short],required:["label"],review:r+"/labels/{label}"),
            rest("list_milestones","Issues",r+"/milestones"),
            rest("create_milestone","Issues",r+"/milestones","POST",.mutation,body:["title":s,"state":Schema.choices(["open","closed"]),"description":s,"due_on":s],bodyRequired:["title"],review:r+"/milestones"),
            rest("edit_milestone","Issues",r+"/milestones/{id}","PATCH",.mutation,fields:n,required:["id"],body:["title":s,"state":Schema.choices(["open","closed"]),"description":s,"due_on":s],review:r+"/milestones/{id}"),
            rest("delete_milestone","Issues",r+"/milestones/{id}","DELETE",.mutation,fields:n,required:["id"],review:r+"/milestones/{id}"),
            rest("list_pull_requests","Pull requests",r+"/pulls",fields:["state":Schema.choices(["open","closed","all"])]),
            rest("search_pull_requests","Pull requests","search/issues",fields:["query":Schema.string(300)],required:["query"]),
            rest("read_pull_request","Pull requests",r+"/pulls/{id}",fields:n,required:["id"]),
            rest("pull_request_files","Pull requests",r+"/pulls/{id}/files",fields:n,required:["id"]),
            rest("open_pull_request","Pull requests",r+"/pulls","POST",.mutation,body:pr,bodyRequired:["title","head","base"],review:r+"/pulls"),
            rest("update_pull_request","Pull requests",r+"/pulls/{id}","PATCH",.mutation,fields:n,required:["id"],body:pr,review:r+"/pulls/{id}"),
            rest("pull_request_reviews","Pull requests",r+"/pulls/{id}/reviews",fields:n,required:["id"]),
            rest("draft_review","Pull requests",r+"/pulls/{id}/reviews","POST",.mutation,fields:n,required:["id"],body:["body":s,"commit_id":Schema.string(64),"comments":Schema.array(Schema.object(["path":Schema.string(1024),"line":id,"side":Schema.choices(["LEFT","RIGHT"]),"body":s],required:["path","line","side","body"]))],review:r+"/pulls/{id}/reviews"),
            rest("submit_review","Pull requests",r+"/pulls/{id}/reviews/{review_id}/events","POST",.mutation,fields:["id":id,"review_id":id],required:["id","review_id"],body:["body":s,"event":Schema.choices(["APPROVE","REQUEST_CHANGES","COMMENT"])],bodyRequired:["event"],review:r+"/pulls/{id}/reviews/{review_id}"),
            rest("inline_comment","Pull requests",r+"/pulls/{id}/comments","POST",.mutation,fields:n,required:["id"],body:["body":s,"commit_id":Schema.string(64),"path":Schema.string(1024),"line":id,"side":Schema.choices(["LEFT","RIGHT"]),"start_line":id,"start_side":Schema.choices(["LEFT","RIGHT"]),"in_reply_to":id],bodyRequired:["body"],review:r+"/pulls/{id}"),
            rest("request_reviewers","Pull requests",r+"/pulls/{id}/requested_reviewers","POST",.mutation,fields:n,required:["id"],body:["reviewers":Schema.array(short),"team_reviewers":Schema.array(short)],review:r+"/pulls/{id}/requested_reviewers"),
            rest("merge_pull_request","Pull requests",r+"/pulls/{id}/merge","PUT",.mutation,fields:n,required:["id"],body:["commit_title":s,"commit_message":s,"sha":Schema.string(64),"merge_method":Schema.choices(["merge","squash","rebase"])],bodyRequired:["sha","merge_method"],review:r+"/pulls/{id}"),
            rest("workflow_status","Actions",r+"/actions/runs"), rest("list_workflows","Actions",r+"/actions/workflows"),
            rest("read_workflow_run","Actions",r+"/actions/runs/{id}",fields:n,required:["id"]),
            rest("workflow_jobs","Actions",r+"/actions/runs/{id}/jobs",fields:n,required:["id"]),
            rest("workflow_logs","Actions",r+"/actions/jobs/{id}/logs",fields:n,required:["id"]),
            rest("check_run_status","Actions",r+"/commits/{sha}/check-runs",fields:["sha":Schema.string(64)],required:["sha"]),
            rest("dispatch_workflow","Actions",r+"/actions/workflows/{id}/dispatches","POST",.mutation,fields:n,required:["id"],body:["ref":short,"inputs":.object(["type":"object","additionalProperties":true,"properties":.object([:])])],bodyRequired:["ref"],review:r+"/actions/workflows/{id}"),
            rest("rerun_workflow","Actions",r+"/actions/runs/{id}/rerun","POST",.mutation,fields:n,required:["id"],review:r+"/actions/runs/{id}"),
            rest("cancel_workflow","Actions",r+"/actions/runs/{id}/cancel","POST",.mutation,fields:n,required:["id"],review:r+"/actions/runs/{id}"),
            rest("list_artifacts","Actions",r+"/actions/artifacts"), rest("artifact_metadata","Actions",r+"/actions/artifacts/{id}",fields:n,required:["id"]),
            rest("delete_artifact","Actions",r+"/actions/artifacts/{id}","DELETE",.mutation,fields:n,required:["id"],review:r+"/actions/artifacts/{id}"),
            rest("pending_deployments","Actions",r+"/actions/runs/{id}/pending_deployments",fields:n,required:["id"]),
            rest("approve_deployment","Actions",r+"/actions/runs/{id}/pending_deployments","POST",.consequential,fields:n,required:["id"],body:["environment_ids":Schema.array(id),"state":Schema.choices(["approved","rejected"]),"comment":s],bodyRequired:["environment_ids","state"],review:r+"/actions/runs/{id}/pending_deployments"),
            rest("list_releases","Releases",r+"/releases"),rest("read_release","Releases",r+"/releases/{id}",fields:n,required:["id"]),
            rest("create_release","Releases",r+"/releases","POST",.mutation,body:release,bodyRequired:["tag_name"],review:r+"/releases"),
            rest("edit_release","Releases",r+"/releases/{id}","PATCH",.mutation,fields:n,required:["id"],body:release,review:r+"/releases/{id}"),
            rest("delete_release","Releases",r+"/releases/{id}","DELETE",.consequential,fields:n,required:["id"],review:r+"/releases/{id}"),
            rest("release_assets","Releases",r+"/releases/{id}/assets",fields:n,required:["id"]),
            rest("delete_release_asset","Releases",r+"/releases/assets/{id}","DELETE",.mutation,fields:n,required:["id"],review:r+"/releases/assets/{id}"),
            rest("dependabot_alerts","Security",r+"/dependabot/alerts"),rest("code_scanning_alerts","Security",r+"/code-scanning/alerts"),rest("secret_scanning_alerts","Security",r+"/secret-scanning/alerts"),
            rest("update_dependabot_alert","Security",r+"/dependabot/alerts/{id}","PATCH",.mutation,fields:n,required:["id"],body:["state":Schema.choices(["dismissed","open"]),"dismissed_reason":s,"dismissed_comment":s],review:r+"/dependabot/alerts/{id}"),
            rest("update_code_scanning_alert","Security",r+"/code-scanning/alerts/{id}","PATCH",.mutation,fields:n,required:["id"],body:["state":Schema.choices(["dismissed","open"]),"dismissed_reason":s,"dismissed_comment":s],review:r+"/code-scanning/alerts/{id}"),
            rest("update_secret_scanning_alert","Security",r+"/secret-scanning/alerts/{id}","PATCH",.consequential,fields:n,required:["id"],body:["state":Schema.choices(["resolved","open"]),"resolution":s,"resolution_comment":s],review:r+"/secret-scanning/alerts/{id}"),
            rest("create_repository","Administration","user/repos","POST",.consequential,body:["name":short,"description":s,"private":Schema.boolean,"auto_init":Schema.boolean,"gitignore_template":short,"license_template":short],bodyRequired:["name","private"],permission:"admin",review:"user/repos"),
            rest("fork_repository","Administration",r+"/forks","POST",.mutation,body:["organization":short,"name":short,"default_branch_only":Schema.boolean],review:r+"/forks"),
            rest("repository_settings","Administration",r,"PATCH",.consequential,body:["name":short,"description":s,"homepage":s,"private":Schema.boolean,"visibility":Schema.choices(["public","private"]),"archived":Schema.boolean,"default_branch":short,"has_issues":Schema.boolean,"has_projects":Schema.boolean,"has_wiki":Schema.boolean,"allow_squash_merge":Schema.boolean,"allow_merge_commit":Schema.boolean,"allow_rebase_merge":Schema.boolean,"delete_branch_on_merge":Schema.boolean],permission:"admin",review:r),
            rest("collaborators","Administration",r+"/collaborators"),
            rest("set_collaborator","Administration",r+"/collaborators/{username}","PUT",.consequential,fields:["username":short],required:["username"],body:["permission":Schema.choices(["pull","triage","push","maintain","admin"])],bodyRequired:["permission"],permission:"admin",review:r+"/collaborators"),
            rest("remove_collaborator","Administration",r+"/collaborators/{username}","DELETE",.consequential,fields:["username":short],required:["username"],permission:"admin",review:r+"/collaborators"),
            rest("list_environments","Administration",r+"/environments"),
            rest("set_environment","Administration",r+"/environments/{environment}","PUT",.consequential,fields:["environment":short],required:["environment"],body:["wait_timer":.object(["type":"integer","minimum":0,"maximum":43200]),"prevent_self_review":Schema.boolean,"reviewers":Schema.array(Schema.object(["type":Schema.choices(["User","Team"]),"id":id],required:["type","id"]))],permission:"admin",review:r+"/environments"),
            rest("delete_environment","Administration",r+"/environments/{environment}","DELETE",.consequential,fields:["environment":short],required:["environment"],permission:"admin",review:r+"/environments/{environment}"),
            rest("list_webhooks","Administration",r+"/hooks"),
            rest("create_webhook","Administration",r+"/hooks","POST",.consequential,body:["name":Schema.choices(["web"]),"active":Schema.boolean,"events":Schema.array(short),"config":Schema.object(["url":s,"content_type":Schema.choices(["json","form"]),"insecure_ssl":Schema.choices(["0"])],required:["url","insecure_ssl"])],bodyRequired:["name","config"],permission:"admin",review:r+"/hooks"),
            rest("delete_webhook","Administration",r+"/hooks/{id}","DELETE",.consequential,fields:n,required:["id"],permission:"admin",review:r+"/hooks/{id}"),
            rest("list_rulesets","Administration",r+"/rulesets"),
            rest("delete_ruleset","Administration",r+"/rulesets/{id}","DELETE",.consequential,fields:n,required:["id"],permission:"admin",review:r+"/rulesets/{id}"),
            rest("branch_protection","Administration",r+"/branches/{branch}/protection",fields:["branch":short],required:["branch"]),
            rest("delete_branch_protection","Administration",r+"/branches/{branch}/protection","DELETE",.consequential,fields:["branch":short],required:["branch"],permission:"admin",review:r+"/branches/{branch}/protection"),
            rest("transfer_repository","Administration",r+"/transfer","POST",.destructive,body:["new_owner":short,"new_name":short,"team_ids":Schema.array(id)],bodyRequired:["new_owner"],permission:"admin",review:r),
            rest("delete_repository","Administration",r,"DELETE",.destructive,permission:"admin",review:r),
            rest("list_secrets","Secrets",r+"/actions/secrets",permission:"admin"),
            rest("list_dependabot_secrets","Secrets",r+"/dependabot/secrets",permission:"admin"),
            rest("list_environment_secrets","Secrets",r+"/environments/{environment}/secrets",fields:["environment":short],required:["environment"],permission:"admin"),
            rest("set_secret","Secrets",r+"/actions/secrets/{name}","PUT",.consequential,fields:["name":short],required:["name"],body:["encrypted_value":s,"key_id":s],bodyRequired:["encrypted_value","key_id"],permission:"admin",review:r+"/actions/secrets",native:true),
            rest("set_dependabot_secret","Secrets",r+"/dependabot/secrets/{name}","PUT",.consequential,fields:["name":short],required:["name"],body:["encrypted_value":s,"key_id":s],bodyRequired:["encrypted_value","key_id"],permission:"admin",review:r+"/dependabot/secrets",native:true),
            rest("set_environment_secret","Secrets",r+"/environments/{environment}/secrets/{name}","PUT",.consequential,fields:["name":short,"environment":short],required:["name","environment"],body:["encrypted_value":s,"key_id":s],bodyRequired:["encrypted_value","key_id"],permission:"admin",review:r+"/environments/{environment}/secrets",native:true),
            rest("delete_secret","Secrets",r+"/actions/secrets/{name}","DELETE",.consequential,fields:["name":short],required:["name"],permission:"admin",review:r+"/actions/secrets"),
            rest("delete_dependabot_secret","Secrets",r+"/dependabot/secrets/{name}","DELETE",.consequential,fields:["name":short],required:["name"],permission:"admin",review:r+"/dependabot/secrets"),
            rest("delete_environment_secret","Secrets",r+"/environments/{environment}/secrets/{name}","DELETE",.consequential,fields:["name":short,"environment":short],required:["name","environment"],permission:"admin",review:r+"/environments/{environment}/secrets")
        ]
    }
    public static var collaboration: [ToolDefinition] {
        let id = Schema.string(200), text = Schema.string(65536)
        return [
            ToolDefinition(name:"list_discussions",group:"Collaboration",description:"List discussions for this repository.",method:"GRAPHQL",path:"discussions",schema:Schema.object([:])),
            ToolDefinition(name:"discussion_comments",group:"Collaboration",description:"Read selected repository discussion comments.",method:"GRAPHQL",path:"discussionComments",schema:Schema.object(["number":Schema.integer],required:["number"])),
            ToolDefinition(name:"create_discussion",group:"Collaboration",description:"Create a repository discussion after native review.",risk:.mutation,permission:"push",method:"GRAPHQL",path:"createDiscussion",schema:Schema.object(["category_id":id,"title":Schema.string(500),"body":text],required:["category_id","title","body"])),
            ToolDefinition(name:"comment_discussion",group:"Collaboration",description:"Comment on a discussion in the selected repository.",risk:.mutation,permission:"push",method:"GRAPHQL",path:"addDiscussionComment",schema:Schema.object(["discussion_id":id,"body":text],required:["discussion_id","body"])),
            ToolDefinition(name:"review_threads",group:"Pull requests",description:"List review threads for a selected pull request.",method:"GRAPHQL",path:"reviewThreads",schema:Schema.object(["number":Schema.integer],required:["number"])),
            ToolDefinition(name:"resolve_thread",group:"Pull requests",description:"Resolve a selected repository review thread after review.",risk:.mutation,permission:"push",method:"GRAPHQL",path:"resolveReviewThread",schema:Schema.object(["thread_id":id],required:["thread_id"])),
            ToolDefinition(name:"ready_pull_request",group:"Pull requests",description:"Mark a selected repository pull request ready for review.",risk:.mutation,permission:"push",method:"GRAPHQL",path:"markPullRequestReadyForReview",schema:Schema.object(["number":Schema.integer],required:["number"])),
            ToolDefinition(name:"linked_projects",group:"Collaboration",description:"Read linked Projects v2 and selected repository items.",method:"GRAPHQL",path:"projectsV2",schema:Schema.object([:])),
            ToolDefinition(name:"add_project_item",group:"Collaboration",description:"Add an issue/PR from the selected repository to a linked project.",risk:.mutation,permission:"push",method:"GRAPHQL",path:"addProjectV2ItemById",schema:Schema.object(["project_id":id,"content_id":id],required:["project_id","content_id"])),
            ToolDefinition(name:"update_project_item",group:"Collaboration",description:"Update a field on a linked project item scoped to this repository.",risk:.mutation,permission:"push",method:"GRAPHQL",path:"updateProjectV2ItemFieldValue",schema:Schema.object(["project_id":id,"item_id":id,"field_id":id,"text":Schema.string(500),"number":.object(["type":"number"]),"date":Schema.string(10),"single_select_option_id":id],required:["project_id","item_id","field_id"]))
        ]
    }
    public static var utilities: [ToolDefinition] {
        [
            ToolDefinition(name:"find_tools",group:"General",description:"Discover up to 12 permitted tools by query; relevant definitions become available in the next request.",schema:Schema.object(["query":Schema.string(200)],required:["query"])),
            ToolDefinition(name:"calculator",group:"General",description:"Evaluate bounded arithmetic without executing code.",schema:Schema.object(["expression":Schema.string(500)],required:["expression"])),
            ToolDefinition(name:"datetime",group:"General",description:"Read current date/time with explicit timezone.",schema:Schema.object(["timezone":Schema.string(100)])),
            ToolDefinition(name:"unit_convert",group:"General",description:"Convert supported length, mass, temperature, and time units.",schema:Schema.object(["value":.object(["type":"number"]),"from":Schema.string(30),"to":Schema.string(30)],required:["value","from","to"])),
            ToolDefinition(name:"file_read",group:"General",description:"Read only an explicitly attached document.",schema:Schema.object(["attachment_id":Schema.string(64)],required:["attachment_id"])),
            ToolDefinition(name:"index_document",group:"General",description:"Index an attached document in the encrypted lexical knowledge base.",schema:Schema.object(["attachment_id":Schema.string(64)],required:["attachment_id"])),
            ToolDefinition(name:"knowledge_base",group:"General",description:"Lexically retrieve bounded excerpts from authorized documents.",schema:Schema.object(["query":Schema.string(500)],required:["query"])),
            ToolDefinition(name:"web_search",group:"General",description:"Search using the explicitly enabled destination; untrusted results.",schema:Schema.object(["query":Schema.string(500)],required:["query"])),
            ToolDefinition(name:"web_fetch",group:"General",description:"Fetch a public HTTPS page with consent; no credentials or redirects.",schema:Schema.object(["url":Schema.string(2048)],required:["url"]))
        ]
    }
}
