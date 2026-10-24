import SwiftUI
import RepoManagerCore
import RepoManagerUI

private extension JSON {
    var repositoryListID:Int { self["id"].int ?? 0 }
    var fileListID:String { self["path"].string ?? "" }
}

struct RepositoriesView: View {
    @Bindable var model: AppModel; @State private var pairing = false; @State private var picker = false; @State private var browse = false; @State private var creating = false
    @State private var disconnecting: GitHubAccount?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    RMPageHeading(String(localized:"Repositories"),detail:String(localized:"One repository and branch for each conversation."))
                    if model.data.accounts.isEmpty {
                        RMEmptyState("Bring your repository into focus",detail:"Connect GitHub in Safari, then choose the repositories the app can access. Your first chat can start with a read-only Plan.",symbol:"folder.badge.plus")
                        Button("Pair GitHub") { pairing = true }.rmProminentButton()
                    } else {
                        if let scope = model.conversation?.repository {
                            RepositoryScopeCard(scope:scope,
                                favorite:model.data.preferences.favoriteRepositories.contains(scope.repositoryID),
                                change:{ picker = true },browse:{ browse = true },toggleFavorite:{
                                    if model.data.preferences.favoriteRepositories.contains(scope.repositoryID) { model.data.preferences.favoriteRepositories.removeAll { $0 == scope.repositoryID } }
                                    else { model.data.preferences.favoriteRepositories.append(scope.repositoryID) }
                                    model.save()
                                },navigate:{ model.selection = $0 }) {
                                    AdministrationView(model:model)
                                }
                        } else {
                            RMEmptyState("Choose your working scope",detail:"Select a repository and branch for this chat. If you have no chat yet, Repo Manager creates one for you. Staged edits stay on this device until you review them.",symbol:"arrow.triangle.branch")
                            Button("Select repository") { picker = true }.rmProminentButton()
                        }
                        RMCard(String(localized:"GitHub accounts")) {
                            ForEach(model.data.accounts) { account in
                                RMRow(account.login,detail:account.expiresAt == nil ? String(localized:"Fine-grained token") : String(localized:"GitHub App connection")) { RMMonogram(account.login) } trailing: {
                                    Menu { Button("Disconnect",systemImage:"xmark.circle",role:.destructive) { disconnecting = account } } label: { Image(systemName:"ellipsis") }
                                        .buttonStyle(RMInlineIconButtonStyle()).padding(.trailing,-RMLayout.inlineIconOutset).accessibilityLabel("Actions for \(account.login)")
                                }
                            }
                            Button { pairing = true } label: { RMRow(String(localized:"Pair another account"),symbol:"plus") }.buttonStyle(RMPressButtonStyle())
                            Button { creating = true } label: { RMRow(String(localized:"Create a repository"),symbol:"folder.badge.plus",accessory:.chevron) }.buttonStyle(RMPressButtonStyle())
                        }
                    }
                }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).navigationBarHidden(true)
            .sheet(isPresented:$pairing) { GitHubPairingView(model:model) }
            .sheet(isPresented:$picker) { RepositoryPickerView(model:model) }
            .fullScreenCover(isPresented:$browse) { FileBrowserView(model:model) }
            .sheet(isPresented:$creating) { NewRepositoryView(model:model) }
            .confirmationDialog("Disconnect \(disconnecting?.login ?? "")?",isPresented:Binding(get:{ disconnecting != nil },set:{ if !$0 { disconnecting = nil } }),titleVisibility:.visible,presenting:disconnecting) { account in
                Button("Disconnect",role:.destructive) { Task { do { try await model.disconnectAccount(account.id) } catch { model.error = (error as? RMError ?? .locked).localizedDescription } } }
            } message: { _ in Text("Its token is removed from this device. Running work for its repositories stops, pending reviews are cancelled, and the API server turns off. Local drafts are kept.") }
        }.onAppear { if DevelopmentFixtures.fileEditorScreenshot { browse = true } }
    }
}
/// This chat's scope: identity first, then everything you can open from it.
private struct RepositoryScopeCard<Settings:View>:View {
    let scope:RepositoryScope
    let favorite:Bool
    let change:() -> Void
    let browse:() -> Void
    let toggleFavorite:() -> Void
    let navigate:(RMWorkspace) -> Void
    let settings:() -> Settings
    var body:some View {
        RMCard(String(localized:"This chat’s repository")) {
            RMRow(scope.fullName,detail:scope.branch) { RMIconTile("folder") } trailing: {
                Button(action:toggleFavorite) { Image(systemName:favorite ? "star.fill" : "star") }
                    .buttonStyle(RMInlineIconButtonStyle()).accessibilityLabel(favorite ? String(localized:"Remove favorite") : String(localized:"Favorite repository"))
                Button("Change",action:change).rmChip()
            }
            link(String(localized:"Browse files"),symbol:"doc.text",action:browse)
            link(String(localized:"Changes"),symbol:"square.and.pencil") { navigate(.changes) }
            link(String(localized:"Issues"),symbol:"circle.dotted") { navigate(.issues) }
            link(String(localized:"Pull requests"),symbol:"arrow.triangle.pull") { navigate(.pullRequests) }
            NavigationLink(destination:settings()) { RMRow(String(localized:"Repository settings"),symbol:"gearshape",accessory:.chevron) }.buttonStyle(RMPressButtonStyle())
        }
    }
    private func link(_ title:String,symbol:String,action:@escaping () -> Void) -> some View {
        Button(action:action) { RMRow(title,symbol:symbol,accessory:.chevron) }.buttonStyle(RMPressButtonStyle())
    }
}

struct NewRepositoryView: View {
    @Bindable var model:AppModel; @Environment(\.dismiss) private var dismiss
    @State private var accountID:Int64?; @State private var name = ""; @State private var detail = ""
    @State private var privateRepository = true; @State private var busy = false; @State private var review:MutationPlan?
    var body:some View {
        NavigationStack {
            RMForm {
                Picker("Account",selection:$accountID) { ForEach(model.data.accounts) { Text($0.login).tag(Optional($0.id)) } }
                TextField("Repository name",text:$name).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Description",text:$detail,axis:.vertical)
                Toggle("Private repository",isOn:$privateRepository)
                Text("The repository starts with a README so branches and reviewed file drafts can be used immediately.").font(RMType.meta)
                Button("Review creation") { prepare() }.rmProminentButton().disabled(busy || !validName || accountID == nil)
                if busy { ProgressView("Preparing repository review…") }
            }.navigationTitle("Create repository").toolbar { Button("Done") { dismiss() } }
            .onAppear { accountID = model.data.accounts.first?.id }
            .sheet(item:$review) { ReviewView(model:model,plan:$0) }
        }
    }
    private var validName:Bool {
        let candidate = name.trimmingCharacters(in:.whitespacesAndNewlines)
        return !candidate.isEmpty && candidate.utf8.count <= 100 && candidate.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45,46,95].contains($0) }
    }
    private func prepare() {
        guard let runtime = model.runtime,let account = model.data.accounts.first(where:{ $0.id == accountID }) else { return }
        if model.conversation == nil { model.newChat(); model.selection = .repositories }
        guard let c = model.conversation else { return }
        let arguments:JSON = .object(["body":.object(["name":.string(name),"description":.string(detail),"private":.bool(privateRepository),"auto_init":true])])
        busy = true
        Task {
            do {
                await model.finishCancellation(c.id)
                guard !model.locked,model.conversation?.id == c.id,model.conversation?.repository == c.repository else { throw RMError.staleReview }
                await runtime.approvals.bind(c.id,scope:c.repository)
                review = try await runtime.approvals.prepareRepositoryCreation(account:account,arguments:arguments,conversationID:c.id,initiatingScope:c.repository)
                await model.refreshWorkspace()
            } catch { model.error = (error as? RMError ?? .invalidInput).localizedDescription }
            busy = false
        }
    }
}
struct RepositoryPickerView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var accountID: Int64?; @State private var repositories: [JSON] = []; @State private var query = ""
    @State private var selected: JSON?; @State private var branch = ""; @State private var branches: [String] = []
    @State private var page = 0; @State private var busy = false; @State private var pairing = false
    @State private var hasMore = true; @State private var loadError:String?; @State private var branchError:String?
    @State private var requestID = UUID(); @State private var branchRequestID = UUID()
    @State private var loadTask:Task<Void,Never>?; @State private var branchTask:Task<Void,Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    HStack(spacing:RMLayout.elementGap) {
                        Menu {
                            Picker("Account",selection:$accountID) { ForEach(model.data.accounts) { Text($0.login).tag(Optional($0.id)) } }
                        } label: {
                            HStack(spacing:RMLayout.unit+2) {
                                Image(systemName:"person.crop.circle")
                                Text(model.data.accounts.first { $0.id == accountID }?.login ?? String(localized:"Select account"))
                                Image(systemName:"chevron.down").font(RMType.meta.weight(.bold)).foregroundStyle(RMPalette.secondary)
                            }
                        }.rmChip().disabled(model.data.accounts.isEmpty)
                        Spacer(minLength:0)
                        Button("Pair account") { pairing = true }.rmChip()
                    }
                    if model.data.accounts.isEmpty {
                        RMEmptyState("No GitHub account",detail:"Connect GitHub first to load your repositories.",symbol:"person.crop.circle.badge.plus")
                    }
                    if let selected {
                        RMCard(selected["full_name"].string ?? String(localized:"Repository")) {
                            HStack(spacing:RMLayout.rowGap) {
                                RMIconTile("arrow.triangle.branch")
                                TextField("Branch",text:$branch).font(RMType.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                                if !branches.isEmpty {
                                    Menu {
                                        Picker("Available branches",selection:$branch) {
                                            if !branches.contains(branch) { Text(branch).tag(branch) }
                                            ForEach(branches,id:\.self) { Text($0).tag($0) }
                                        }
                                    } label: { Image(systemName:"chevron.up.chevron.down") }
                                        .buttonStyle(RMInlineIconButtonStyle()).accessibilityLabel("Available branches")
                                }
                            }.padding(.horizontal,RMLayout.cardInset).frame(minHeight:RMLayout.rowHeight)
                            if !branch.isEmpty,!validBranch {
                                Text("Enter a valid branch name, without spaces or control characters.").font(RMType.meta).foregroundStyle(RMPalette.red)
                                    .padding(.leading,RMLayout.dividerInset).padding([.trailing,.vertical],RMLayout.cardInset).frame(maxWidth:.infinity,alignment:.leading)
                            }
                        }
                        Button(model.draft != nil && model.draft?.scope.connectionID != model.data.accounts.first(where:{ $0.id == accountID })?.connectionID ? String(localized:"Reconnect this draft to selected account") : String(localized:"Use this repository and branch")) { choose(selected) }
                            .rmProminentButton().disabled(!validBranch || busy)
                        if let branchError {
                            RMInlineNotice(title:"Branches could not load",detail:branchError,symbol:"exclamationmark.circle",isError:true)
                            Button("Retry branches") { select(selected) }.rmSecondaryButton()
                        }
                    }
                    if let loadError {
                        RMInlineNotice(title:"Repositories could not load",detail:loadError,symbol:"exclamationmark.circle",isError:true)
                        Button("Try again",action:load).rmSecondaryButton()
                    } else if !busy,accountID != nil,visibleRepositories.isEmpty {
                        RMEmptyState(query.isEmpty ? "No repositories" : "No matches",detail:query.isEmpty ? "No repositories are available to this connection. Choose repository access on GitHub, then try again." : "No loaded repositories match your search.",symbol:"folder")
                    }
                    if !visibleRepositories.isEmpty {
                        RMCard(query.isEmpty ? String(localized:"Repositories") : String(localized:"Matches")) {
                            ForEach(visibleRepositories,id:\.repositoryListID) { repo in
                                let favorite = repo["id"].int.map { model.data.preferences.favoriteRepositories.contains(Int64($0)) } ?? false
                                Button { select(repo) } label: {
                                    RMRow(repo["full_name"].string ?? String(localized:"Repository"),detail:repo["description"].string,
                                          accessory:.selected(selected?["id"].int != nil && selected?["id"].int == repo["id"].int)) {
                                        RMIconTile(repo["private"].bool == true ? "lock" : "folder")
                                    } trailing: {
                                        if favorite { Image(systemName:"star.fill").font(RMType.label).foregroundStyle(RMPalette.secondary).accessibilityLabel("Favorite") }
                                    }
                                }.buttonStyle(RMPressButtonStyle()).accessibilityIdentifier("repository.pick.\(repo["id"].int ?? 0)")
                            }
                        }
                    }
                    if accountID != nil,hasMore,page > 0 { Button("Load more repositories",action:load).rmSecondaryButton().disabled(busy) }
                    if accountID != nil,!hasMore,page >= 20 { Text("The first 2,000 repositories are loaded.").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
                    if busy { ProgressView("Loading repositories…").frame(maxWidth:.infinity) }
                }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground())
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text:$query,prompt:"Search repositories").navigationTitle("Repository").toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of:accountID) { _, _ in branchTask?.cancel(); branchRequestID = UUID(); repositories = []; branches = []; selected = nil; branchError = nil; page = 0; hasMore = true; load() }
            .onAppear { accountID = model.conversation?.repository?.accountID ?? model.data.accounts.first?.id }
            .onDisappear { loadTask?.cancel(); branchTask?.cancel(); requestID = UUID(); branchRequestID = UUID() }
            .sheet(isPresented:$pairing) { GitHubPairingView(model:model) }
        }
    }
    private var validBranch:Bool { !branch.isEmpty && (try? InputValidation.ref(branch)) != nil }
    private var visibleRepositories:[JSON] { repositories.filter { query.isEmpty || ($0["full_name"].string ?? "").localizedCaseInsensitiveContains(query) } }
    private func load() {
        loadTask?.cancel(); requestID = UUID(); busy = false
        guard let accountID,let runtime = model.runtime else { return }; busy = true
        let ticket = requestID; let requestedPage = page + 1; let lease = model.lifecycleID
        loadError = nil
        loadTask = Task {
            defer { if requestID == ticket { busy = false } }
            do {
                let rows = try await runtime.github.repositories(accountID:accountID,page:requestedPage).array ?? []
                guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,self.accountID == accountID,requestID == ticket else { return }
                var seen = Set(repositories.map(\.repositoryListID))
                repositories += rows.filter { $0["id"].int != nil && seen.insert($0.repositoryListID).inserted }
                page = requestedPage; hasMore = rows.count == 100 && requestedPage < 20
            } catch { if !Task.isCancelled,requestID == ticket,!model.locked { loadError = (error as? RMError ?? .connection).localizedDescription } }
        }
    }
    private func select(_ repository: JSON) {
        selected = repository; branch = repository["default_branch"].string ?? "main"; branches = []; branchError = nil
        guard let account = model.data.accounts.first(where:{ $0.id == accountID }), let id = repository["id"].int,
              let owner = repository["owner"]["login"].string, let name = repository["name"].string else { return }
        let scope = RepositoryScope(accountID:account.id,connectionID:account.connectionID,repositoryID:Int64(id),owner:owner,name:name,branch:branch)
        branchTask?.cancel(); branchRequestID = UUID(); let ticket = branchRequestID; let lease = model.lifecycleID
        branchTask = Task { do {
            let rows = try await model.runtime?.github.read(ToolCatalog.named("list_branches"),arguments:.object([:]),scope:scope)
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,branchRequestID == ticket,self.accountID == scope.accountID,selected?["id"].int == id else { return }
            branches = rows?.array?.compactMap { $0["name"].string } ?? []
        } catch {
            if !Task.isCancelled,branchRequestID == ticket,!model.locked,model.lifecycleID == lease,
               self.accountID == scope.accountID,selected?["id"].int == id {
                branchError = (error as? RMError ?? .connection).localizedDescription
            }
        } }
    }
    private func choose(_ repository: JSON) {
        guard let account = model.data.accounts.first(where:{ $0.id == accountID }), let id = repository["id"].int,
              let owner = repository["owner"]["login"].string, let name = repository["name"].string, (try? InputValidation.ref(branch)) != nil else { return }
        let scope = RepositoryScope(accountID:account.id,connectionID:account.connectionID,repositoryID:Int64(id),owner:owner,name:name,branch:branch)
        Task { await model.setRepository(scope); if model.conversation?.repository == scope { dismiss() } }
    }
}
struct FileBrowserView: View {
    @Environment(\.rmUsesAdaptiveBars) private var adaptive
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var paths: [JSON] = []; @State private var query = ""; @State private var editor: FileSelection?
    @State private var loading = false; @State private var loadError:String?; @State private var loadTask:Task<Void,Never>?
    @State private var requestID = UUID()
    @Environment(\.dynamicTypeSize) private var typeSize
    struct FileSelection: Identifiable { var id: String; var mode: String; var scope:RepositoryScope; var conversationID:UUID }
    var body: some View {
        if adaptive { DuoFileBrowserView(model:model) } else { classicBody }
    }
    private var classicBody: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 820 && !typeSize.isAccessibilitySize
            NavigationStack {
                HStack(spacing:0) {
                    fileList.frame(width:wide ? 330 : nil)
                    if wide {
                        Divider()
                        if let editor {
                            FileEditorView(model:model,path:editor.id,mode:editor.mode,scope:editor.scope,conversationID:editor.conversationID,embedded:true).id(editor.id)
                        } else {
                            ContentUnavailableView("Choose a file",systemImage:"doc.text",description:Text("Read a file alongside the repository tree. Edits remain in this conversation until you stage them."))
                        }
                    }
                }.background(RMPageBackground()).navigationTitle("Files")
                .toolbar { Button("Done") { dismiss() } }
                .onAppear(perform:load)
                .onDisappear { loadTask?.cancel(); requestID = UUID() }
                .sheet(item:Binding(get:{ wide ? nil : editor },set:{ if !wide { editor = $0 } })) {
                    FileEditorView(model:model,path:$0.id,mode:$0.mode,scope:$0.scope,conversationID:$0.conversationID)
                }
            }
        }
    }
    private var fileList:some View {
        List {
            Section {
                Text("\(model.conversation?.repository?.fullName ?? "") · \(model.conversation?.repository?.branch ?? "")").font(RMType.meta)
                Button("Refresh",action:load).rmTextButton().disabled(loading)
                if loading { ProgressView("Loading files…") }
                if let loadError { RMInlineNotice(title:"Files could not load",detail:loadError,symbol:"exclamationmark.circle",isError:true) }
                if !loading,loadError == nil,paths.isEmpty { Text("No files are available for this branch.").foregroundStyle(RMPalette.secondary) }
            }
            ForEach(paths.filter { query.isEmpty || ($0["path"].string ?? "").localizedCaseInsensitiveContains(query) },id:\.fileListID) { entry in
                Button {
                    if let path = entry["path"].string,let scope = model.conversation?.repository,let id = model.selectedConversationID {
                        editor = FileSelection(id:path,mode:entry["mode"].string ?? "",scope:scope,conversationID:id)
                    }
                } label: {
                    HStack(spacing:RMLayout.elementGap) {
                        Image(systemName:entry["type"].string == "tree" ? "folder" : "doc.text").foregroundStyle(RMPalette.secondary)
                        Text(entry["path"].string ?? "").font(.system(.footnote,design:.monospaced)).lineLimit(2)
                        Spacer()
                        if entry["staged"].bool == true { Image(systemName:"circle.fill").font(.system(size:6)).foregroundStyle(RMPalette.accentText).accessibilityLabel("Staged") }
                    }.padding(.vertical,RMLayout.unit)
                }.disabled(entry["type"].string == "tree")
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).searchable(text:$query,prompt:"Find a file")
    }
    private func load() {
        guard !loading,let scope = model.conversation?.repository, let id = model.selectedConversationID, let runtime = model.runtime else { return }
        loading = true; loadError = nil; requestID = UUID(); let ticket = requestID, lease = model.lifecycleID
        loadTask = Task {
          defer { if requestID == ticket { loading = false } }
          do {
            let d = try await runtime.workspace.open(scope,conversationID:id); let tree = try await runtime.github.tree(scope,sha:d.baseSHA)
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket,model.selectedConversationID == id,model.conversation?.repository == scope else { return }
            let current = await runtime.workspace.currentDraft(id) ?? d
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket else { return }
            paths = Array(ToolRegistry.overlay(tree:tree,draft:current).prefix(2000))
            if tree["truncated"].bool == true { loadError = String(localized:"GitHub returned an incomplete tree. Some files are missing from this list.") }
          } catch { if !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket { loadError = (error as? RMError ?? .connection).localizedDescription } }
        }
    }
}
struct FileEditorView: View {
    @Bindable var model: AppModel; let path: String; let mode: String; let scope:RepositoryScope; let conversationID:UUID; var embedded = false
    @Environment(\.dismiss) private var dismiss; @State private var text = ""; @State private var loading = true
    @State private var masked = false
    @State private var originalText = ""; @State private var staging = false; @State private var readError:String?; @State private var staged = false
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:RMLayout.rowGap) {
                Text(path).font(.system(.caption,design:.monospaced)).padding(.horizontal)
                if loading { ProgressView("Opening file…").padding(.horizontal,RMLayout.pageInset) }
                if let readError { RMInlineNotice(title:"File could not open",detail:readError,symbol:"exclamationmark.circle",isError:true).padding(.horizontal,RMLayout.pageInset) }
                if masked { RMInlineNotice(title:"Credentials are masked",detail:String(localized:"Staging this displayed text replaces detected values with placeholders."),symbol:"lock.shield").padding(.horizontal,RMLayout.pageInset) }
                if model.conversation?.mode == .plan {
                    HStack { Text("Use Act mode to stage edits.").font(RMType.meta).foregroundStyle(RMPalette.secondary); Spacer(); Button("Switch to Act") { model.stop(); model.editConversation { $0.mode = .act } }.rmTextButton() }.padding(.horizontal,RMLayout.pageInset)
                }
                if staged { Label("Staged on this device. Open Changes to review.",systemImage:"checkmark.circle").font(RMType.meta).foregroundStyle(RMPalette.accentText).padding(.horizontal,RMLayout.pageInset) }
                if ["120000","160000"].contains(mode) { ContentUnavailableView("Metadata only",systemImage:"link",description:Text("Symlinks and submodules cannot be edited.")) }
                else { TextEditor(text:$text).font(.system(.body,design:.monospaced)).scrollContentBackground(.hidden).padding(.horizontal,RMLayout.pageInset).disabled(loading || staging || readError != nil).accessibilityLabel("File contents") }
            }.navigationTitle(embedded ? String(localized:"Files") : String(localized:"File editor")).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction) { if !embedded { Button("Done") { dismiss() } } }
                ToolbarItem(placement:.confirmationAction) { Button(staging ? String(localized:"Staging…") : String(localized:"Stage edit")) {
                    guard model.selectedConversationID == conversationID,model.conversation?.repository == scope else { model.error = RMError.staleReview.localizedDescription; return }
                    let snapshot = text; staging = true
                    Task {
                        defer { staging = false }
                        let result = await model.executeTool("write_file",arguments:.object(["path":.string(path),"content":.string(snapshot)]))
                        guard !model.locked,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { return }
                        if result?.status == .success { originalText = snapshot; staged = true; if !embedded { dismiss() } }
                        else { model.error = result?.detail }
                    }
                }.disabled(loading || staging || readError != nil || text == originalText || model.conversation?.mode != .act || model.selectedConversationID != conversationID || model.conversation?.repository != scope || ["120000","160000"].contains(mode)) }
            }.task {
                let lease = model.lifecycleID
                do { if let file = try await model.runtime?.workspace.read(path,scope:scope,conversationID:conversationID), let bytes = file.updated, let value = String(data:bytes,encoding:.utf8) {
                    try Task.checkCancellation()
                    guard !model.locked,model.lifecycleID == lease,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { throw RMError.staleReview }
                    let scan = RepositorySecretScanner.scan(value)
                    let key = "\(scope.repositoryID):\(scope.branch):\(path)"
                    originalText = scan.redacted; text = model.conversation?.fileEditorDrafts?[key] ?? scan.redacted; masked = !scan.findings.isEmpty
                } else { throw RMError.unsupported } }
                catch { if !Task.isCancelled,!model.locked,model.lifecycleID == lease { readError = (error as? RMError ?? .connection).localizedDescription } }; loading = false
            }
            .onChange(of:text) { _,value in if !loading { model.updateFileDraft(value,path:path,scope:scope,in:conversationID) } }
        }
    }
}

struct DuoFileBrowserView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var paths: [JSON] = []; @State private var query = ""; @State private var editor: FileSelection?
    @State private var loading = false; @State private var loadError:String?; @State private var loadTask:Task<Void,Never>?
    @State private var requestID = UUID()
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    struct FileSelection: Identifiable { var id: String; var mode: String; var scope:RepositoryScope; var conversationID:UUID }
    var body: some View {
        NavigationSplitView(preferredCompactColumn:$compactColumn) {
            fileList
                .navigationTitle("Files")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Close files",systemImage:"xmark") { dismiss() }.accessibilityIdentifier("files.close") }
                }
        } detail: {
            if let editor {
                DuoFileEditorView(model:model,path:editor.id,mode:editor.mode,scope:editor.scope,
                               conversationID:editor.conversationID,embedded:true,closeBrowser:{ dismiss() })
                    .id(editor.id)
            } else {
                NavigationStack {
                    ContentUnavailableView("Choose a file",systemImage:"doc.text",description:Text("Read a file alongside the repository tree. Edits remain in this conversation until you stage them."))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(RMPageBackground())
        .onAppear(perform:load)
        .onDisappear { loadTask?.cancel(); requestID = UUID() }
    }
    private var fileList:some View {
        List(selection:Binding<String?>(get:{ editor?.id },set:selectFile)) {
            Section {
                Text("\(model.conversation?.repository?.fullName ?? "") · \(model.conversation?.repository?.branch ?? "")").font(RMType.meta)
                Button("Refresh",action:load).rmTextButton().disabled(loading)
                if loading { ProgressView("Loading files…") }
                if let loadError { RMInlineNotice(title:"Files could not load",detail:loadError,symbol:"exclamationmark.circle",isError:true) }
                if !loading,loadError == nil,paths.isEmpty { Text("No files are available for this branch.").foregroundStyle(RMPalette.secondary) }
            }
            ForEach(paths.filter { query.isEmpty || ($0["path"].string ?? "").localizedCaseInsensitiveContains(query) },id:\.fileListID) { entry in
                NavigationLink(value:entry.fileListID) {
                    HStack(spacing:RMLayout.elementGap) {
                        Image(systemName:entry["type"].string == "tree" ? "folder" : "doc.text").foregroundStyle(RMPalette.secondary)
                        Text(entry["path"].string ?? "").font(.system(.footnote,design:.monospaced)).lineLimit(2)
                        Spacer()
                        if entry["staged"].bool == true { Image(systemName:"circle.fill").font(.system(size:6)).foregroundStyle(RMPalette.accentText).accessibilityLabel("Staged") }
                    }.padding(.vertical,RMLayout.unit)
                }.tag(entry.fileListID).disabled(entry["type"].string == "tree")
                    .listRowBackground(editor?.id == entry.fileListID ? RMPalette.accentSoft : Color.clear)
                    .accessibilityAddTraits(editor?.id == entry.fileListID ? .isSelected : [])
                    .accessibilityIdentifier("files.row.\(entry.fileListID)")
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).searchable(text:$query,prompt:"Find a file")
    }
    private func selectFile(_ path:String?) {
        guard let path else { editor = nil; compactColumn = .sidebar; return }
        guard let entry = paths.first(where:{ $0.fileListID == path && $0["type"].string == "blob" }),
              let scope = model.conversation?.repository,let id = model.selectedConversationID else { return }
        editor = FileSelection(id:path,mode:entry["mode"].string ?? "",scope:scope,conversationID:id)
        compactColumn = .detail
    }
    private func load() {
        guard !loading,let scope = model.conversation?.repository, let id = model.selectedConversationID, let runtime = model.runtime else { return }
        loading = true; loadError = nil; requestID = UUID(); let ticket = requestID, lease = model.lifecycleID
        loadTask = Task {
          defer { if requestID == ticket { loading = false } }
          do {
            let d = try await runtime.workspace.open(scope,conversationID:id); let tree = try await runtime.github.tree(scope,sha:d.baseSHA)
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket,model.selectedConversationID == id,model.conversation?.repository == scope else { return }
            let current = await runtime.workspace.currentDraft(id) ?? d
            guard !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket else { return }
            paths = Array(ToolRegistry.overlay(tree:tree,draft:current).prefix(2000))
            if DevelopmentFixtures.fileEditorScreenshot,editor == nil,
               let file = paths.first(where:{ $0["type"].string == "blob" }),let path = file["path"].string {
                editor = FileSelection(id:path,mode:file["mode"].string ?? "",scope:scope,conversationID:id)
                compactColumn = .detail
            }
            if tree["truncated"].bool == true { loadError = String(localized:"GitHub returned an incomplete tree. Some files are missing from this list.") }
          } catch { if !Task.isCancelled,!model.locked,model.lifecycleID == lease,requestID == ticket { loadError = (error as? RMError ?? .connection).localizedDescription } }
        }
    }
}
struct DuoFileEditorView: View {
    @Bindable var model: AppModel; let path: String; let mode: String; let scope:RepositoryScope; let conversationID:UUID; var embedded = false
    var closeBrowser: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss; @State private var text = ""; @State private var loading = true
    @State private var masked = false
    @State private var originalText = ""; @State private var staging = false; @State private var readError:String?; @State private var staged = false
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:RMLayout.rowGap) {
                Text(path).font(.system(.caption,design:.monospaced)).padding(.horizontal)
                if loading { ProgressView("Opening file…").padding(.horizontal,RMLayout.pageInset) }
                if let readError { RMInlineNotice(title:"File could not open",detail:readError,symbol:"exclamationmark.circle",isError:true).padding(.horizontal,RMLayout.pageInset) }
                if masked { RMInlineNotice(title:"Credentials are masked",detail:String(localized:"Staging this displayed text replaces detected values with placeholders."),symbol:"lock.shield").padding(.horizontal,RMLayout.pageInset) }
                if model.conversation?.mode == .plan {
                    HStack { Text("Use Act mode to stage edits.").font(RMType.meta).foregroundStyle(RMPalette.secondary); Spacer(); Button("Switch to Act") { model.stop(); model.editConversation { $0.mode = .act } }.rmTextButton() }.padding(.horizontal,RMLayout.pageInset)
                }
                if !loading,readError == nil,text != originalText {
                    Label("Unstaged edits",systemImage:"pencil.line")
                        .font(RMType.meta).foregroundStyle(RMPalette.secondary).padding(.horizontal,RMLayout.pageInset)
                        .accessibilityIdentifier("files.editStatus")
                } else if staged {
                    VStack(alignment:.leading,spacing:RMLayout.unit) {
                        Label("Staged locally",systemImage:"checkmark.circle")
                            .font(RMType.meta).foregroundStyle(RMPalette.accentText).accessibilityIdentifier("files.editStatus")
                        Button("Review changes",systemImage:"arrow.right") {
                            if let closeBrowser { closeBrowser() } else { dismiss() }
                            model.selection = .changes
                        }.rmTextButton().accessibilityIdentifier("files.reviewChanges")
                    }.padding(.horizontal,RMLayout.pageInset)
                }
                if ["120000","160000"].contains(mode) { ContentUnavailableView("Metadata only",systemImage:"link",description:Text("Symlinks and submodules cannot be edited.")) }
                else { TextEditor(text:$text).font(.system(.body,design:.monospaced)).scrollContentBackground(.hidden).padding(.horizontal,RMLayout.pageInset).disabled(loading || staging || readError != nil).accessibilityLabel("File contents").accessibilityIdentifier("files.editor") }
            }.background(RMPageBackground()).navigationTitle(path.split(separator:"/").last.map(String.init) ?? path).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    if !embedded { Button("Done",systemImage:"xmark") { dismiss() } }
                }
                ToolbarItem(placement:.confirmationAction) { Button(staging ? String(localized:"Staging…") : String(localized:"Stage edit"),systemImage:"square.and.arrow.down") {
                    guard model.selectedConversationID == conversationID,model.conversation?.repository == scope else { model.error = RMError.staleReview.localizedDescription; return }
                    let snapshot = text; staging = true
                    Task {
                        defer { staging = false }
                        let result = await model.executeTool("write_file",arguments:.object(["path":.string(path),"content":.string(snapshot)]))
                        guard !model.locked,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { return }
                        if result?.status == .success {
                            let draft = await model.runtime?.workspace.currentDraft(conversationID)
                            guard !model.locked,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { return }
                            originalText = snapshot; staged = draft?.changes.contains(where:{ $0.path == path }) == true
                            if !embedded { dismiss() }
                        }
                        else { model.error = result?.detail }
                    }
                }.disabled(loading || staging || readError != nil || text == originalText || model.conversation?.mode != .act || model.selectedConversationID != conversationID || model.conversation?.repository != scope || ["120000","160000"].contains(mode)) }
            }.task {
                let lease = model.lifecycleID
                do { if let file = try await model.runtime?.workspace.read(path,scope:scope,conversationID:conversationID), let bytes = file.updated, let value = String(data:bytes,encoding:.utf8) {
                    try Task.checkCancellation()
                    guard !model.locked,model.lifecycleID == lease,model.selectedConversationID == conversationID,model.conversation?.repository == scope else { throw RMError.staleReview }
                    let scan = RepositorySecretScanner.scan(value)
                    let key = "\(scope.repositoryID):\(scope.branch):\(path)"
                    originalText = scan.redacted; text = model.conversation?.fileEditorDrafts?[key] ?? scan.redacted; masked = !scan.findings.isEmpty
                    staged = file.original != file.updated || file.originalMode != file.mode
                } else { throw RMError.unsupported } }
                catch { if !Task.isCancelled,!model.locked,model.lifecycleID == lease { readError = (error as? RMError ?? .connection).localizedDescription } }; loading = false
            }
            .onChange(of:text) { _,value in if !loading { model.updateFileDraft(value,path:path,scope:scope,in:conversationID) } }
        }
    }
}
