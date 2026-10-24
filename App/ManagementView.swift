import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct ManagementView: View {
    @Environment(\.rmUsesAdaptiveBars) private var adaptive
    @Bindable var model: AppModel; let destination: RMWorkspace
    @State private var result: JSON = .null; @State private var busy = false; @State private var tool: ToolDefinition?
    @State private var selectedEntity: Entity?; @State private var query = ""; @State private var loadedItems:[ManagementItem] = []
    @State private var loadError:String?; @State private var loadTask:Task<Void,Never>?; @State private var requestID = UUID()
    @Environment(\.rmWorkspaceVisible) private var visible
    @Environment(\.dynamicTypeSize) private var typeSize
    struct Entity: Identifiable { var id: String; var value: JSON; var scope:RepositoryScope; var conversationID:UUID }
    private struct ManagementItem:Identifiable { let id:String; let value:JSON }
    private var group: String { destination.catalogGroup }
    private var initialTool: String {
        switch destination { case .issues: "list_issues"; case .pullRequests: "list_pull_requests"; case .actions: "workflow_status"; case .releases: "list_releases"; case .security: "dependabot_alerts"; default: "activity" }
    }
    private var rows: [JSON] { result.array ?? result["workflow_runs"].array ?? result["jobs"].array ?? result["artifacts"].array ?? result["items"].array ?? [] }
    var body: some View {
        if adaptive { DuoManagementView(model:model,destination:destination) } else { classicBody }
    }
    private var classicBody: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 920 && !typeSize.isAccessibilitySize
            NavigationStack {
                HStack(spacing:0) {
                    listing.frame(maxWidth:wide ? 350 : .infinity)
                    if wide {
                        Divider()
                        if let selectedEntity {
                            EntityView(model:model,entity:selectedEntity.value,group:group,scope:selectedEntity.scope,conversationID:selectedEntity.conversationID).id(selectedEntity.id)
                        } else { ContentUnavailableView("Choose an item",systemImage:"sidebar.right",description:Text("Keep the list and details side by side.")) }
                    }
                }
                .onChange(of:visible) { _,value in if value && result == .null { load() } else if !value { cancelLoad() } }
                .onChange(of:model.conversation?.repository) { _,_ in cancelLoad(); result = .null; loadedItems = []; selectedEntity = nil; if visible { load() } }
                .onDisappear { cancelLoad() }
                .sheet(item:$tool) { ToolFormView(model:model,definition:$0,initialArguments:.object([:])) }
                .sheet(item:Binding(get:{ wide ? nil : selectedEntity },set:{ if !wide { selectedEntity = $0 } })) {
                    EntityView(model:model,entity:$0.value,group:group,scope:$0.scope,conversationID:$0.conversationID)
                }
                .task { if visible { load() } }
            }
        }
    }
    private var filtered:[ManagementItem] { loadedItems.filter { query.isEmpty || $0.value.pretty.localizedCaseInsensitiveContains(query) } }
    private var listing:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                RMPageHeading(destination.title,detail:model.conversation?.repository.map { "\($0.fullName) · \($0.branch)" } ?? "") {
                    if model.conversation?.repository != nil {
                        Menu {
                            ForEach(ToolCatalog.all.filter { $0.group == group && !$0.nativeOnly }) { definition in Button(definition.displayName,systemImage:definition.symbol) { tool = definition } }
                            if destination == .issues { ForEach(ToolCatalog.collaboration.filter { $0.group == "Collaboration" }) { d in Button(d.displayName,systemImage:d.symbol) { tool = d } } }
                        } label: { Image(systemName:"wrench.and.screwdriver") }.rmIconButton().accessibilityLabel("Tools")
                        Button { load() } label: {
                            if busy { ProgressView() } else { Image(systemName:"arrow.clockwise") }
                        }.rmIconButton().disabled(busy).accessibilityLabel("Refresh")
                    }
                }
                if model.conversation?.repository == nil {
                    RMEmptyState("No repository yet",detail:"Choose a repository for this chat to see its \(destination.title).",symbol:destination.symbol)
                    Button("Choose a repository") { model.selection = .repositories }.rmProminentButton()
                }
                if destination == .activity,!model.activity.isEmpty {
                    RMCard(String(localized:"Operation journal")) {
                        ForEach(model.activity) { receipt in
                            RMRow(RMLocalization.fieldName(receipt.operation),detail:"\(receipt.scope.fullName) · \(receipt.date.formatted(.relative(presentation:.named)))") {
                                RMIconTile("clock.arrow.circlepath")
                            } trailing: { RMBadge(RMLocalization.fieldName(receipt.state.rawValue),tint:receipt.state == .uncertain ? RMPalette.red : nil) }
                        }
                    }
                }
                if !filtered.isEmpty {
                    RMCard(footer:String(localized:"The first 30 results. Use Tools to search GitHub or open a specific item.")) {
                        ForEach(filtered) { item in
                            Button { if let scope = model.conversation?.repository,let id = model.selectedConversationID { selectedEntity = Entity(id:item.id,value:item.value,scope:scope,conversationID:id) } } label: {
                                RMRow(GitHubItem.title(item.value),detail:GitHubItem.detail(item.value),accessory:.chevron) {
                                    RMIconTile(destination.symbol,tint:GitHubItem.tint(item.value))
                                } trailing: { EmptyView() }
                            }.buttonStyle(RMPressButtonStyle())
                        }
                    }
                }
                if let loadError {
                    RMInlineNotice(title:"Could not refresh",detail:loadError,symbol:"exclamationmark.circle",isError:true)
                    Button("Try again",action:load).rmSecondaryButton()
                } else if result != .null && rows.isEmpty {
                    RMEmptyState("Nothing to show yet",detail:"No items were returned for this repository. Refresh later or use Tools to inspect a specific item.",symbol:destination.symbol)
                    if result.object != nil {
                        DisclosureGroup("Response details") { Text(GitHubRedaction.clean(result).pretty).font(.system(.footnote,design:.monospaced)).textSelection(.enabled) }
                            .font(RMType.detail).padding(RMLayout.cardInset).rmSurface()
                    }
                } else if !query.isEmpty,filtered.isEmpty {
                    RMEmptyState("No matches",detail:"No loaded items match “\(query)”.",symbol:"magnifyingglass")
                }
            }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
        }.background(RMPageBackground()).searchable(text:$query,prompt:"Filter loaded items").navigationBarHidden(true)
    }
    private func cancelLoad() { loadTask?.cancel(); loadTask = nil; requestID = UUID(); busy = false }
    private func load() {
        guard visible, !busy, let runtime = model.runtime, let scope = model.conversation?.repository else { return }; busy = true
        requestID = UUID(); let ticket = requestID, lease = model.lifecycleID
        loadError = nil
        let id = model.selectedConversationID
        loadTask = Task {
          defer { if requestID == ticket { busy = false } }
          do {
            let response = try await runtime.github.read(ToolCatalog.named(initialTool),arguments:.object([:]),scope:scope)
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket,model.selectedConversationID == id,model.conversation?.repository == scope else { return }
            result = response
            var seen = Set<String>()
            loadedItems = rows.compactMap { row in
                let identity = row["id"].string ?? row["id"].int.map(String.init) ?? row["number"].int.map { "number:\($0)" } ?? row["url"].string ?? UUID().uuidString
                return seen.insert(identity).inserted ? ManagementItem(id:identity,value:row) : nil
            }
            await model.refreshWorkspace()
          } catch { if !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket { loadError = (error as? RMError ?? .connection).localizedDescription } }
        }
    }
}
struct EntityView: View {
    @Bindable var model: AppModel; let entity: JSON; let group: String; let scope:RepositoryScope; let conversationID:UUID
    var closeDetail: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss; @State private var tool: ToolDefinition?; @State private var linkTask: Task<Void,Never>?
    @State private var files:[JSON] = []; @State private var selectedPath:String?
    @Environment(\.rmWorkspaceVisible) private var visible
    private var number: Int? { entity["number"].int ?? entity["id"].int }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    VStack(alignment:.leading,spacing:RMLayout.rowGap) {
                        RMEyebrow("\(RMLocalization.text(group)) · #\(number ?? 0)")
                        Text(entity["title"].string ?? entity["name"].string ?? String(localized:"Details"))
                            .font(RMType.title).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                        HStack(spacing:RMLayout.elementGap) {
                            if let state = GitHubItem.state(entity) { RMBadge(state.capitalized,tint:GitHubItem.tint(entity)) }
                            RMBadge(scope.branch,symbol:"arrow.triangle.branch")
                        }
                    }
                    if let body = entity["body"].string { RMMarkdown(RepositorySecretScanner.scan(body).redacted) }
                    if let raw = entity["html_url"].string,let url = URL(string:raw),(try? URLPolicy.validate(url)) != nil,url.host == "github.com" {
                        Link(destination:url) { Label("Open on GitHub",systemImage:"safari") }.rmSecondaryButton()
                    }
                    if group == "Pull requests",!files.isEmpty {
                        RMCard(String(localized:"Changed files · first 30"),dividerInset:RMLayout.cardInset) {
                            ForEach(Array(files.enumerated()),id:\.offset) { _,file in
                                DisclosureGroup(isExpanded:Binding(get:{ selectedPath == file["filename"].string },set:{ selectedPath = $0 ? file["filename"].string : nil })) {
                                    if let patch = file["patch"].string {
                                        ScrollView(.horizontal) { Text(RepositorySecretScanner.scan(patch).redacted).font(.system(.footnote,design:.monospaced)).textSelection(.enabled).padding(.vertical,RMLayout.rowGap) }
                                    } else { Text("GitHub did not supply a text diff for this file. Binary or oversized content requires separate inspection.").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
                                } label: {
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(file["filename"].string ?? String(localized:"File")).font(.system(.subheadline,design:.monospaced)).foregroundStyle(RMPalette.text)
                                        Text("\(file["status"].string ?? "changed") · +\(file["additions"].int ?? 0) −\(file["deletions"].int ?? 0)").font(RMType.meta).foregroundStyle(RMPalette.secondary)
                                    }
                                }.tint(RMPalette.secondary).padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap)
                            }
                        }
                    }
                    actionCard(String(localized:"Actions"),actions.filter { primaryActions.contains($0.name) })
                    if group == "Issues" { Button("Start issue-to-PR conversation",systemImage:"arrow.triangle.branch") {
                        guard model.selectedConversationID == conversationID,model.conversation?.repository == scope else { model.error = RMError.staleReview.localizedDescription; return }
                        model.newChat(); let createdID = model.selectedConversationID
                        Task {
                            await model.setRepository(scope)
                            guard !model.locked,model.selectedConversationID == createdID,model.conversation?.repository == scope else { return }
                            model.editConversation { $0.mode = .plan; $0.draft = String(localized:"Plan a fix for @issue:\(number ?? 0).\nUntrusted issue context:\n\(GitHubRedaction.clean(entity).pretty)\nInspect relevant code, then prepare staged edits in Act mode and a reviewed pull request.") }; dismiss()
                        }
                    }.rmSecondaryButton() }
                    actionCard(String(localized:"More tools"),actions.filter { !primaryActions.contains($0.name) })
                    DisclosureGroup("Response details") { Text(GitHubRedaction.clean(entity).pretty).font(.system(.footnote,design:.monospaced)).textSelection(.enabled) }
                        .font(RMType.detail).tint(RMPalette.secondary).padding(RMLayout.cardInset).rmSurface()
                }.padding(RMLayout.pageInset).frame(maxWidth:760,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).navigationTitle(RMLocalization.text(group)).navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { if let closeDetail { closeDetail() } else { dismiss() } } }
            .sheet(item:$tool) { d in ToolFormView(model:model,definition:d,initialArguments:initial(d),boundConversationID:conversationID,boundScope:scope) }
            .task(id:visible) {
                guard visible,group == "Pull requests",let number,let runtime = model.runtime else { return }
                do {
                    let response = try await runtime.github.read(ToolCatalog.named("pull_request_files"),arguments:.object(["id":.number(Double(number))]),scope:scope)
                    try Task.checkCancellation(); guard !model.locked,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { return }
                    files = response.array ?? []
                } catch { if !Task.isCancelled { model.error = (error as? RMError ?? .connection).localizedDescription } }
            }
        }
    }
    private var actions:[ToolDefinition] {
        ToolCatalog.all.filter { $0.group == group && !$0.nativeOnly && ($0.schema["properties"]["id"] != .null || $0.risk != .read) }
    }
    private var primaryActions:Set<String> {
        switch group {
        case "Pull requests": ["draft_review","update_pull_request","merge_pull_request"]
        case "Issues": ["edit_issue","comment_issue","close_issue"]
        case "Actions": ["workflow_jobs","rerun_workflow","cancel_workflow"]
        case "Releases": ["edit_release","publish_release","upload_release_asset"]
        case "Security": ["update_dependabot_alert","update_code_scanning_alert","update_secret_scanning_alert"]
        default: []
        }
    }
    @ViewBuilder private func actionCard(_ title:String,_ values:[ToolDefinition]) -> some View {
        if !values.isEmpty {
            RMCard(title) {
                ForEach(values) { d in
                    Button { tool = d } label: { RMRow(d.displayName,detail:d.riskLabel,symbol:d.symbol,accessory:.chevron) }.buttonStyle(RMPressButtonStyle())
                }
            }
        }
    }
    private func initial(_ d: ToolDefinition) -> JSON {
        var values: [String:JSON] = [:]
        if let number { if d.schema["properties"]["id"] != .null { values["id"] = .number(Double(number)) }; if d.schema["properties"]["number"] != .null { values["number"] = .number(Double(number)) } }
        if let fields = d.schema["properties"]["body"]["properties"].object {
            var body: [String:JSON] = [:]; for key in fields.keys where entity[key] != .null { body[key] = entity[key] }; values["body"] = .object(body)
        }
        return .object(values)
    }
}
struct AdministrationView: View {
    @Bindable var model: AppModel; @State private var tool: ToolDefinition?; @State private var secrets = false
    var body: some View {
        RMForm {
            Section { Text(model.conversation?.repository?.fullName ?? String(localized:"Select a repository first.")); Text("Every change shows its before/after state. Permission, protection, visibility, secret, deployment, transfer and deletion changes additionally require native authentication.").font(RMType.meta) }
            Section("Repository administration") { ForEach(ToolCatalog.all.filter { $0.group == "Administration" }) { d in Button(d.displayName,systemImage:d.symbol) { tool = d } } }
            Section("Secrets") { Button("Secure secret entry and management",systemImage:"key") { secrets = true } }
        }.navigationTitle("Repository settings")
        .sheet(item:$tool) { ToolFormView(model:model,definition:$0,initialArguments:.object([:])) }
        .sheet(isPresented:$secrets) { SecretsView(model:model) }
    }
}
struct ToolFormView: View {
    @Bindable var model: AppModel; let definition: ToolDefinition; let initialArguments: JSON
    @Environment(\.dismiss) private var dismiss; @State private var arguments = ""; @State private var fields: JSON = .object([:]); @State private var advanced = false; @State private var result: ToolResult?; @State private var active = false
    var boundConversationID:UUID? = nil; var boundScope:RepositoryScope? = nil
    @State private var conversationID:UUID?; @State private var scope:RepositoryScope?; @State private var initialized = false
    @State private var invalidFields = Set<String>()
    var body: some View {
        NavigationStack {
            RMForm {
                Section(definition.displayName) {
                    Text(definition.localizedDescription).font(RMType.meta)
                    LabeledContent("Scope",value:model.conversation?.repository?.fullName ?? String(localized:"Conversation attachments only"))
                    LabeledContent("Mode",value:model.conversation?.mode.title ?? String(localized:"Plan"))
                    if model.conversation == nil {
                        Text("Start a chat to give this tool its own context and draft.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
                        Button("Start a chat") {
                            model.newChat(); conversationID = model.selectedConversationID; scope = model.conversation?.repository
                        }.rmSecondaryButton()
                    }
                    if definition.risk != .read && model.conversation?.mode != .act { Button("Switch this chat to Act") { model.stop(); model.editConversation { $0.mode = .act } } }
                }
                Section("Arguments") {
                    Toggle("Advanced JSON editor",isOn:$advanced).font(RMType.meta).accessibilityIdentifier("tool.advancedJSON")
                    if advanced { TextEditor(text:$arguments).font(.system(.footnote,design:.monospaced)).frame(minHeight:200).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("Tool arguments JSON").accessibilityIdentifier("tool.argumentsJSON") }
                    else { SchemaFields(schema:definition.schema,value:$fields,invalidFields:$invalidFields) }
                    DisclosureGroup("Supported fields") { Text(definition.schema.pretty).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }
                }
                Button(definition.risk == .read ? String(localized:"Read selected scope") : definition.risk == .localEdit ? String(localized:"Stage locally") : String(localized:"Prepare native review")) { execute() }
                    .rmProminentButton().disabled(active || !argumentsValid || model.selectedConversationID == nil || (definition.risk != .read && model.conversation?.mode != .act))
                if !argumentsValid { Text("Complete the required fields and fix invalid values to continue.").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
                if active { ProgressView(definition.risk == .read ? "Reading…" : "Preparing…") }
                if let result {
                    Section("Result · \(RMLocalization.text(result.status.rawValue))") {
                        Text(result.detail).font(.system(.footnote,design:.monospaced)).textSelection(.enabled)
                        if result.status == .approval { Button("Open review") { model.selection = .changes; dismiss() } }
                    }
                }
            }.navigationTitle("\(definition.localizedGroup) tool").toolbar { Button("Done") { dismiss() } }
            .onAppear {
                guard !initialized else { return }; initialized = true
                fields = Self.sample(definition.schema,initial:initialArguments); arguments = fields.pretty
                conversationID = boundConversationID ?? model.selectedConversationID; scope = boundConversationID == nil ? model.conversation?.repository : boundScope
            }
            .onChange(of:advanced) { _, value in
                if value { arguments = fields.pretty }
                else if let parsed = try? JSON.parse(Data(arguments.utf8)),(try? Schema.validate(parsed,against:definition.schema)) != nil { fields = parsed; invalidFields = [] }
                else { advanced = true }
            }
        }
    }
    private var argumentsValid:Bool {
        if advanced { guard let parsed = try? JSON.parse(Data(arguments.utf8)) else { return false }; return (try? Schema.validate(parsed,against:definition.schema)) != nil }
        return invalidFields.isEmpty && (try? Schema.validate(fields,against:definition.schema)) != nil
    }
    private func execute() {
        guard !model.locked,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { model.error = RMError.staleReview.localizedDescription; return }
        do { let value = advanced ? try JSON.parse(Data(arguments.utf8)) : fields; try Schema.validate(value,against:definition.schema)
            active = true; Task { result = await model.executeTool(definition.name,arguments:value); active = false }
        } catch { model.error = RMError.invalidInput.localizedDescription }
    }
    static func sample(_ schema: JSON, initial: JSON = .null) -> JSON {
        if initial != .null, schema["type"].string != "object" { return initial }
        switch schema["type"].string {
        case "object":
            var values = initial.object ?? [:]; let fields = schema["properties"].object ?? [:]
            for key in schema["required"].array?.compactMap(\.string) ?? [] where values[key] == nil { values[key] = sample(fields[key] ?? .null) }
            return .object(values)
        case "array": return .array([])
        case "boolean": return false
        case "integer": return .number(Double(schema["minimum"].int ?? 1))
        case "number": return 0
        default: return schema["enum"].array?.first ?? ""
        }
    }
}
struct ChangesView: View {
    @Bindable var model: AppModel; @State private var message = String(localized:"Reviewed repository changes"); @State private var reviewing: MutationPlan?
    @State private var discarding = false
    @State private var resolving: ConflictSelection?
    struct ConflictSelection: Identifiable { let id = UUID(); var conflict: MergeConflict }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    RMPageHeading(String(localized:"Changes"),detail:String(localized:"Staged edits stay on this device until you review and publish them."))
                    if let draft = model.draft {
                        RMCard(String(localized:"Draft")) {
                            RMRow(draft.scope.fullName,detail:draft.scope.branch) { RMIconTile("folder") } trailing: {
                                RMBadge(draft.changes.count == 1 ? String(localized:"1 file") : String(localized:"\(draft.changes.count) files"))
                            }
                            RMRow(String(localized:"Base commit"),symbol:"number",accessory:.value(String(draft.baseSHA.prefix(12))))
                            RMRow(String(localized:"Revision"),symbol:"clock",accessory:.value(String(draft.revision.uuidString.prefix(8))))
                            HStack(spacing:RMLayout.rowGap) {
                                RMIconTile("text.cursor")
                                TextField("Commit message",text:$message).font(RMType.body)
                            }.padding(.horizontal,RMLayout.cardInset).frame(minHeight:RMLayout.rowHeight)
                        }
                        Button("Review complete draft") { Task { do { await model.finishCancellation(draft.conversationID); guard model.selectedConversationID == draft.conversationID,model.conversation?.repository == draft.scope,!model.locked else { throw RMError.staleReview }; if let plan = try await model.runtime?.workspace.prepare(draft.conversationID,message:message) { reviewing = plan; await model.refreshWorkspace() } } catch { model.error = (error as? RMError ?? .conflict).localizedDescription } } }.rmProminentButton().disabled(draft.changes.isEmpty || !model.conflicts.isEmpty || message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        HStack(spacing:RMLayout.elementGap) {
                            Button("Restage") { Task { do { try await model.runtime?.workspace.restage(draft.conversationID); await model.refreshWorkspace() } catch { model.error = (error as? RMError ?? .conflict).localizedDescription } } }
                                .rmSecondaryButton().accessibilityHint("Compares and restages onto the advanced branch")
                            Button("Discard",role:.destructive) { discarding = true }.rmSecondaryButton()
                                .confirmationDialog("Discard all staged changes in this draft?",isPresented:$discarding,titleVisibility:.visible) {
                                    Button("Discard draft",role:.destructive) { Task { do { try await model.runtime?.workspace.discard(draft.conversationID); await model.refreshWorkspace() } catch { model.error = RMError.locked.localizedDescription } } }
                                } message: { Text("Nothing on GitHub changes. Local checkpoints for this draft remain.") }
                        }
                    } else {
                        RMEmptyState("No staged changes",detail:"Use Act mode in a chat to stage edits here before publication.",symbol:"square.and.pencil")
                        Button(model.conversation?.repository == nil ? String(localized:"Choose a repository") : String(localized:"Open current chat")) { model.selection = model.conversation?.repository == nil ? .repositories : .chat }.rmProminentButton()
                    }
                    if !model.conflicts.isEmpty {
                        RMCard(String(localized:"Conflicts")) {
                            ForEach(model.conflicts) { conflict in
                                Button { resolving = ConflictSelection(conflict:conflict) } label: { RMRow(conflict.path,detail:String(localized:"Choose the resolved text"),symbol:"exclamationmark.triangle",tint:RMPalette.red,accessory:.chevron) }
                                    .buttonStyle(RMPressButtonStyle())
                            }
                        }
                    }
                    if let changes = model.draft?.changes,!changes.isEmpty {
                        RMCard(String(localized:"Staged files"),dividerInset:RMLayout.cardInset) {
                            ForEach(changes) { change in
                                DisclosureGroup {
                                    ScrollView(.horizontal) { Text(TextDiff.review(change)).font(.system(.footnote,design:.monospaced)).textSelection(.enabled).padding(.vertical,RMLayout.elementGap) }
                                } label: {
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(change.path).font(.system(.subheadline,design:.monospaced)).foregroundStyle(RMPalette.text)
                                        Text("Mode \(change.mode)").font(RMType.meta).foregroundStyle(RMPalette.secondary)
                                    }
                                }.tint(RMPalette.secondary).padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap)
                            }
                        }
                    }
                    if !model.pending.isEmpty {
                        RMCard(String(localized:"Pending reviews")) {
                            ForEach(model.pending) { plan in
                                Button { reviewing = plan } label: {
                                    RMRow(RMLocalization.fieldName(plan.operation),detail:String(localized:"\(plan.scope.fullName) · expires \(plan.expires.formatted(.relative(presentation:.named)))"),symbol:"checkmark.shield",accessory:.chevron)
                                }.buttonStyle(RMPressButtonStyle())
                            }
                        }
                    }
                    let checkpoints = model.checkpoints.filter { $0.draft.conversationID == model.selectedConversationID }
                    if !checkpoints.isEmpty {
                        RMCard(String(localized:"Local checkpoints")) {
                            ForEach(checkpoints) { checkpoint in
                                RMRow(checkpoint.title) { RMIconTile("clock.arrow.circlepath") } trailing: {
                                    Button("Restore") { Task { do { try await model.runtime?.workspace.restoreCheckpoint(checkpoint.id,conversationID:checkpoint.draft.conversationID); await model.refreshWorkspace() } catch { model.error = (error as? RMError ?? .conflict).localizedDescription } } }.rmChip()
                                }
                            }
                        }
                    }
                    let uncertain = model.activity.filter { $0.state == .uncertain }
                    if !uncertain.isEmpty {
                        RMCard(String(localized:"Needs reconciliation"),footer:String(localized:"These writes may or may not have reached GitHub. Inspect each before retrying.")) {
                            ForEach(uncertain) { receipt in
                                NavigationLink { ReconciliationView(model:model,receipt:receipt) } label: {
                                    RMRow(RMLocalization.fieldName(receipt.operation),detail:receipt.scope.fullName,symbol:"questionmark.circle",tint:RMPalette.red,accessory:.chevron)
                                }.buttonStyle(RMPressButtonStyle())
                            }
                        }
                    }
                }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).navigationTitle("Changes").navigationBarHidden(true)
            .task { await model.refreshWorkspace() }
            .sheet(item:$reviewing) { ReviewView(model:model,plan:$0) }
            .sheet(item:$resolving) { ConflictView(model:model,conflict:$0.conflict) }
        }
    }
}
struct ReviewView: View {
    @Bindable var model: AppModel; let plan: MutationPlan
    @Environment(\.dismiss) private var dismiss; @State private var typed = ""; @State private var busy = false; @State private var error: String?
    @State private var specificConfirmation = false
    var body: some View {
        NavigationStack {
            RMForm {
                Section("Target") {
                    LabeledContent("Action",value:plan.operation.replacingOccurrences(of:"_",with:" "))
                    LabeledContent("Account",value:model.data.accounts.first(where:{ $0.id == plan.scope.accountID })?.login ?? String(plan.scope.accountID))
                    LabeledContent("Repository",value:plan.scope.fullName); LabeledContent("Repository ID",value:String(plan.scope.repositoryID))
                    LabeledContent("Branch",value:plan.scope.branch); LabeledContent("Expected commit",value:plan.expectedHead)
                    Text("Approval applies only to this snapshot. Account, branch, target or draft changes require a fresh review.").font(RMType.meta)
                }
                if let draft = plan.draft {
                    ForEach(draft.changes) { change in Section("\(change.path) · \(change.mode)") { Text(TextDiff.review(change)).font(.system(.footnote,design:.monospaced)).textSelection(.enabled) } }
                    if let parent = plan.arguments["merge_parent"].string { LabeledContent("Second merge parent",value:parent) }
                    LabeledContent("Commit message",value:plan.arguments["message"].string ?? "")
                } else if plan.operation.contains("secret") {
                    Section("Secret change") {
                        LabeledContent("Name",value:plan.arguments["name"].string ?? ""); LabeledContent("Environment",value:plan.arguments["environment"].string ?? "repository")
                        LabeledContent("Operation",value:plan.operation.hasPrefix("delete") ? String(localized:"Delete") : plan.before["exists"].bool == false ? String(localized:"Create") : String(localized:"Replace"))
                        Text("The value is encrypted with GitHub's public key and never shown to chat. An existing value cannot be retrieved.")
                    }
                } else {
                    Section("Before") { Text(plan.before.pretty).font(.system(.footnote,design:.monospaced)).textSelection(.enabled) }
                    Section("After / requested change") { Text(GitHubRedaction.clean(plan.arguments).pretty).font(.system(.footnote,design:.monospaced)).textSelection(.enabled) }
                }
                if plan.risk == .consequential || plan.risk == .destructive { Section("Additional confirmation") {
                    Text("Native device-owner authentication is required. Review visibility, permissions, protection and deployment effects before continuing.")
                    Toggle("Confirm \(plan.operation.replacingOccurrences(of:"_",with:" ")) for \(plan.scope.fullName)",isOn:$specificConfirmation)
                    if plan.risk == .destructive { TextField("Enter \(plan.scope.fullName)",text:$typed).autocorrectionDisabled().textInputAutocapitalization(.never) }
                } }
                if let error { Text(error).foregroundStyle(.red) }
                if Date() > plan.expires { Text("This review expired. Cancel and prepare the change again.").foregroundStyle(.orange) }
                Button(plan.risk == .destructive ? String(localized:"Authenticate and confirm destructive action") : String(localized:"Approve this snapshot"),role:plan.risk == .destructive ? .destructive : nil) { confirm() }
                    .rmProminentButton()
                    .disabled(busy || Date() > plan.expires || ((plan.risk == .consequential || plan.risk == .destructive) && !specificConfirmation) || (plan.risk == .destructive && typed != plan.scope.fullName))
                    .accessibilityIdentifier("review.approve")
                if busy { ProgressView("Confirming reviewed change…") }
            }.navigationTitle("Review changes").toolbar { Button("Cancel") { Task { await model.runtime?.approvals.cancel(plan.id); await model.refreshWorkspace(); dismiss() } }.disabled(busy) }
        }
    }
    private func confirm() { busy = true; Task { do { try await model.approve(plan,typedName:typed); dismiss() } catch { self.error = (error as? RMError ?? .uncertainWrite).localizedDescription; await model.refreshWorkspace() }; busy = false } }
}
struct ConflictView: View {
    @Bindable var model: AppModel; let conflict: MergeConflict; @Environment(\.dismiss) private var dismiss
    @State private var resolution = ""
    var body: some View {
        NavigationStack { RMForm {
            LabeledContent("Path",value:conflict.path)
            Section("Base") { Text(masked(conflict.base)).font(.system(.caption,design:.monospaced)) }
            Section("Your draft") { Text(masked(conflict.ours)).font(.system(.caption,design:.monospaced)) }
            Section("Remote") { Text(masked(conflict.theirs)).font(.system(.caption,design:.monospaced)) }
            Section("Resolved text") { TextEditor(text:$resolution).font(.system(.footnote,design:.monospaced)).frame(minHeight:160) }
            Button("Stage resolution") { Task { do { if let id = model.selectedConversationID { try await model.runtime?.workspace.resolveConflict(id,path:conflict.path,bytes:Data(resolution.utf8)); await model.refreshWorkspace(); dismiss() } } catch { model.error = (error as? RMError ?? .conflict).localizedDescription } } }
        }.navigationTitle("Conflict review").toolbar { Button("Cancel") { dismiss() } }.onAppear { resolution = masked(conflict.ours) } }
    }
    private func masked(_ value: Data?) -> String { RepositorySecretScanner.scan(value.flatMap { String(data:$0,encoding:.utf8) } ?? String(localized:"[absent or binary]")).redacted }
}
struct ReconciliationView: View {
    @Bindable var model: AppModel; let receipt: MutationReceipt
    @State private var state = ""; @State private var outcome = ""
    var body: some View { RMForm {
        Text("A write response was lost. Inspect GitHub's current state before any retry.")
        Button("Fetch current repository state") { Task { do { state = try await model.runtime?.approvals.reconciliation(receipt.id).pretty ?? "" } catch { model.error = (error as? RMError ?? .connection).localizedDescription } } }
        Text(state).font(.system(.footnote,design:.monospaced)).textSelection(.enabled)
        TextField("Describe the observed outcome",text:$outcome)
        Button("Authenticate and acknowledge reconciliation") { Task { do { try await model.runtime?.approvals.acknowledgeReconciliation(receipt.id,observedOutcome:outcome); await model.refreshWorkspace() } catch { model.error = (error as? RMError ?? .authentication).localizedDescription } } }.disabled(state.isEmpty || outcome.isEmpty)
    }.navigationTitle("Reconcile operation") }
}
struct SecretsView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var value = ""; @State private var environment = ""; @State private var kind = "actions"
    @State private var metadata = ""; @State private var review: MutationPlan?
    var body: some View {
        NavigationStack { RMForm {
            Text("Agents can access names and status only. Enter values in this native secure field.").font(RMType.meta)
            Picker("Scope",selection:$kind) { Text("Repository Actions").tag("actions"); Text("Environment Actions").tag("environment"); Text("Dependabot").tag("dependabot") }
            if kind == "environment" { TextField("Environment",text:$environment).autocorrectionDisabled().textInputAutocapitalization(.never) }
            TextField("Secret name",text:$name).autocorrectionDisabled().textInputAutocapitalization(.characters)
            SecureField("Secret value",text:$value).privacySensitive().autocorrectionDisabled().textInputAutocapitalization(.never)
            Button("List names and status") { list() }
            Text(metadata).font(.system(.caption,design:.monospaced))
            Button("Encrypt value and prepare review") { prepare() }.disabled(name.isEmpty || value.isEmpty)
            Button("Prepare secret deletion",role:.destructive) { remove() }.disabled(name.isEmpty)
        }.navigationTitle("Secrets").toolbar { Button("Done") { value = ""; dismiss() } }
        .sheet(item:$review) { ReviewView(model:model,plan:$0) }.onDisappear { value = "" } }
    }
    private func list() { Task { let tool = kind == "environment" ? "list_environment_secrets" : kind == "dependabot" ? "list_dependabot_secrets" : "list_secrets"; metadata = await model.executeTool(tool,arguments:kind == "environment" ? .object(["environment":.string(environment)]) : .object([:]))?.detail ?? "" } }
    private func prepare() {
        guard let runtime = model.runtime, let c = model.conversation, let scope = c.repository else { return }
        let bytes = Data(value.utf8); value = ""
        let secretName = name, secretEnvironment = kind == "environment" ? environment : nil, dependabot = kind == "dependabot"
        Task { do {
            await model.finishCancellation(c.id)
            guard !model.locked,model.conversation?.id == c.id,model.conversation?.repository == scope else { throw RMError.staleReview }
            await runtime.approvals.bind(c.id,scope:scope)
            let (tool,args) = try await runtime.github.secretPlanArguments(scope:scope,name:secretName,environment:secretEnvironment,dependabot:dependabot,value:bytes)
            guard !model.locked,model.conversation?.id == c.id,model.conversation?.repository == scope else { throw RMError.staleReview }
            review = try await runtime.approvals.prepare(ToolCatalog.named(tool),arguments:args,scope:scope,conversationID:c.id,native:true)
            await model.refreshWorkspace()
        } catch { model.error = (error as? RMError ?? .forbidden).localizedDescription } }
    }
    private func remove() { Task { let tool = kind == "environment" ? "delete_environment_secret" : kind == "dependabot" ? "delete_dependabot_secret" : "delete_secret"; var args: [String:JSON] = ["name":.string(name)]; if kind == "environment" { args["environment"] = .string(environment) }; let r = await model.executeTool(tool,arguments:.object(args)); if let id = r?.approvalID { review = model.pending.first { $0.id == id } } } }
}

/// Presentation for tool catalog entries: one name, symbol and risk wording everywhere.
extension ToolDefinition {
    var symbol:String { risk == .read ? "doc.text.magnifyingglass" : risk == .localEdit ? "square.and.pencil" : "checkmark.shield" }
    var riskLabel:String { risk == .read ? String(localized:"Reads") : risk == .localEdit ? String(localized:"Stages on this device") : String(localized:"Opens a review") }
}
/// GitHub list rows share one title, status line and state tint.
enum GitHubItem {
    static func title(_ row:JSON) -> String {
        row["title"].string ?? row["name"].string ?? row["tag_name"].string ?? row["type"].string ?? String(localized:"Item \(row["number"].int ?? row["id"].int ?? 0)")
    }
    static func state(_ row:JSON) -> String? { row["conclusion"].string ?? row["state"].string ?? row["status"].string }
    static func detail(_ row:JSON) -> String {
        [row["number"].int.map { "#\($0)" },row["state"].string ?? row["status"].string,row["conclusion"].string,row["user"]["login"].string]
            .compactMap { $0 }.joined(separator:" · ")
    }
    /// Emerald marks open or successful work, red a failure; everything else is neutral.
    static func tint(_ row:JSON) -> Color? {
        if let conclusion = row["conclusion"].string { return conclusion == "success" ? RMPalette.accentText : ["failure","timed_out","action_required","startup_failure"].contains(conclusion) ? RMPalette.red : nil }
        return row["state"].string == "open" ? RMPalette.accentText : nil
    }
}

private struct DuoManagementView: View {
    @Bindable var model: AppModel; let destination: RMWorkspace
    @State private var result: JSON = .null; @State private var busy = false; @State private var tool: ToolDefinition?
    @State private var selectedEntity: Entity?; @State private var query = ""; @State private var loadedItems:[ManagementItem] = []
    @State private var loadError:String?; @State private var loadTask:Task<Void,Never>?; @State private var requestID = UUID()
    @Environment(\.rmWorkspaceVisible) private var visible
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    struct Entity: Identifiable { var id: String; var value: JSON; var scope:RepositoryScope; var conversationID:UUID }
    private struct ManagementItem:Identifiable { let id:String; let value:JSON }
    private var group: String { destination.catalogGroup }
    private var initialTool: String {
        switch destination { case .issues: "list_issues"; case .pullRequests: "list_pull_requests"; case .actions: "workflow_status"; case .releases: "list_releases"; case .security: "dependabot_alerts"; default: "activity" }
    }
    private var rows: [JSON] { result.array ?? result["workflow_runs"].array ?? result["jobs"].array ?? result["artifacts"].array ?? result["items"].array ?? [] }
    var body: some View {
        NavigationSplitView(preferredCompactColumn:$compactColumn) {
            listing.navigationTitle(destination.title)
        } detail: {
            if let selectedEntity {
                EntityView(model:model,entity:selectedEntity.value,group:group,scope:selectedEntity.scope,
                           conversationID:selectedEntity.conversationID,closeDetail:{ compactColumn = .sidebar })
                    .id(selectedEntity.id)
            } else {
                ContentUnavailableView("Choose an item",systemImage:"sidebar.right",description:Text("Keep the list and details side by side."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of:visible) { _,value in if value && result == .null { load() } else if !value { cancelLoad() } }
        .onChange(of:model.conversation?.repository) { _,_ in cancelLoad(); result = .null; loadedItems = []; selectedEntity = nil; compactColumn = .sidebar; if visible { load() } }
        .onDisappear { cancelLoad() }
        .sheet(item:$tool) { ToolFormView(model:model,definition:$0,initialArguments:.object([:])) }
        .task { if visible { load() } }
    }
    private var filtered:[ManagementItem] { loadedItems.filter { query.isEmpty || $0.value.pretty.localizedCaseInsensitiveContains(query) } }
    private var listing:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                RMPageHeading(destination.title,detail:model.conversation?.repository.map { "\($0.fullName) · \($0.branch)" } ?? "") {
                    if model.conversation?.repository != nil {
                        Menu {
                            ForEach(ToolCatalog.all.filter { $0.group == group && !$0.nativeOnly }) { definition in Button(definition.displayName,systemImage:definition.symbol) { tool = definition } }
                            if destination == .issues { ForEach(ToolCatalog.collaboration.filter { $0.group == "Collaboration" }) { d in Button(d.displayName,systemImage:d.symbol) { tool = d } } }
                        } label: { Image(systemName:"wrench.and.screwdriver") }.rmIconButton().accessibilityLabel("Tools")
                        Button { load() } label: {
                            if busy { ProgressView() } else { Image(systemName:"arrow.clockwise") }
                        }.rmIconButton().disabled(busy).accessibilityLabel("Refresh")
                    }
                }
                if model.conversation?.repository == nil {
                    RMEmptyState("No repository yet",detail:"Choose a repository for this chat to see its \(destination.title).",symbol:destination.symbol)
                    Button("Choose a repository") { model.selection = .repositories }.rmProminentButton()
                }
                if destination == .activity,!model.activity.isEmpty {
                    RMCard(String(localized:"Operation journal")) {
                        ForEach(model.activity) { receipt in
                            RMRow(RMLocalization.fieldName(receipt.operation),detail:"\(receipt.scope.fullName) · \(receipt.date.formatted(.relative(presentation:.named)))") {
                                RMIconTile("clock.arrow.circlepath")
                            } trailing: { RMBadge(RMLocalization.fieldName(receipt.state.rawValue),tint:receipt.state == .uncertain ? RMPalette.red : nil) }
                        }
                    }
                }
                if !filtered.isEmpty {
                    RMCard(footer:String(localized:"The first 30 results. Use Tools to search GitHub or open a specific item.")) {
                        ForEach(filtered) { item in
                            Button { if let scope = model.conversation?.repository,let id = model.selectedConversationID { selectedEntity = Entity(id:item.id,value:item.value,scope:scope,conversationID:id); compactColumn = .detail } } label: {
                                RMRow(GitHubItem.title(item.value),detail:GitHubItem.detail(item.value),accessory:.chevron) {
                                    RMIconTile(destination.symbol,tint:GitHubItem.tint(item.value))
                                } trailing: { EmptyView() }
                            }.buttonStyle(RMPressButtonStyle())
                        }
                    }
                }
                if let loadError {
                    RMInlineNotice(title:"Could not refresh",detail:loadError,symbol:"exclamationmark.circle",isError:true)
                    Button("Try again",action:load).rmSecondaryButton()
                } else if result != .null && rows.isEmpty {
                    RMEmptyState("Nothing to show yet",detail:"No items were returned for this repository. Refresh later or use Tools to inspect a specific item.",symbol:destination.symbol)
                    if result.object != nil {
                        DisclosureGroup("Response details") { Text(GitHubRedaction.clean(result).pretty).font(.system(.footnote,design:.monospaced)).textSelection(.enabled) }
                            .font(RMType.detail).padding(RMLayout.cardInset).rmSurface()
                    }
                } else if !query.isEmpty,filtered.isEmpty {
                    RMEmptyState("No matches",detail:"No loaded items match “\(query)”.",symbol:"magnifyingglass")
                }
            }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
        }.background(RMPageBackground()).searchable(text:$query,prompt:"Filter loaded items")
    }
    private func cancelLoad() { loadTask?.cancel(); loadTask = nil; requestID = UUID(); busy = false }
    private func load() {
        guard visible, !busy, let runtime = model.runtime, let scope = model.conversation?.repository else { return }; busy = true
        requestID = UUID(); let ticket = requestID, lease = model.lifecycleID
        loadError = nil
        let id = model.selectedConversationID
        loadTask = Task {
          defer { if requestID == ticket { busy = false } }
          do {
            let response = try await runtime.github.read(ToolCatalog.named(initialTool),arguments:.object([:]),scope:scope)
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket,model.selectedConversationID == id,model.conversation?.repository == scope else { return }
            result = response
            var seen = Set<String>()
            loadedItems = rows.compactMap { row in
                let identity = row["id"].string ?? row["id"].int.map(String.init) ?? row["number"].int.map { "number:\($0)" } ?? row["url"].string ?? UUID().uuidString
                return seen.insert(identity).inserted ? ManagementItem(id:identity,value:row) : nil
            }
            await model.refreshWorkspace()
          } catch { if !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket { loadError = (error as? RMError ?? .connection).localizedDescription } }
        }
    }
}
