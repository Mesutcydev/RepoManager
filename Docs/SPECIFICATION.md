# Repo Manager — full product specification

Version 1.0 · 11 October 2026 · implementation source: `project.yml`, app, Core and UI packages.

This document preserves the requested product scope and its later additions. It is a requirements document. Dated implementation/QA evidence and unmet release prerequisites are recorded separately; a requirement listed here is not a claim that its live-service or physical-device test has passed.

## Product and boundaries

Repo Manager is an independent native SwiftUI GitHub application at `/Users/m/Desktop/RepoManager`, with independent local Git history. It supports iPhone, iPad and Apple silicon Mac Catalyst, minimum OS 26, Swift 6 and Xcode 27. Developers inspect repositories, manage GitHub entities, prepare changes through native screens or chat, and publish immutable reviewed operations.

The visual/interaction reference is the current OnDeviceMax production workbench and host chat. Adapt only selected source into independent packages; preserve MIT attribution and file hashes. Do not edit, build, regenerate, clean, commit or change reference dependencies. Record both source and Git-state verification, including externally observed Git metadata changes.

Later user additions: Apple system Foundation Models and entitlement-gated OS 27 Private Cloud Compute, adaptive reasoning, OpenCode Zen in addition to Go, premium repository-case brand/onboarding/splash, bounded background networking, and App Store Connect/TestFlight delivery after the release gates. Apple-managed system model assets are allowed; imported model runtimes remain excluded.

Excluded: vision/camera/OCR/image generation, local model import/download/embedding models, CoreAI/MLX/llama/Whisper, MCP/arbitrary plugins, shell or imported-code execution, companion apps, full Git clones, GitLab/Bitbucket/GitHub Enterprise Server and organization-wide billing. No VPN/proxy Network Extension is required.

## Navigation, typography and motion

One conversation home and a leading sidebar; no bottom tabs. Destinations: Chats, Repositories, Changes, Issues, Pull requests, Actions, Releases, Security, Activity, Providers, Tools, Voice and API server. Settings opens from the sidebar header; repository settings stay scoped to the selected repository.

Visited workspaces remain mounted and retain drafts, selections, filters and scroll positions. Retained hidden hosts are detached from UIKit; their controller/state stays alive, while decorative motion, hit testing and accessibility stop. The modal drawer also detaches the obscured native host behind a noninteractive in-memory backdrop; it reattaches the same controller on return. Backdrops have no persistent file and are released with the protected presentation state. Available width adds file/detail and PR/diff columns without changing navigation. Sheets are native; keyboard focus and dismissal remain native. The keyboard-hide control stays at the leading edge of the composer accessory row.

The approved graphite repository-case mark uses ceramic and emerald accents. Semantic SF typography, restrained tracking, readable code/metadata typography, generous composition and small interruptible feedback replace generic promotional tiles. Launch settles the case/file layers into the final mark; there is no looping decorative wait. Reduce Motion uses a short fade. Dynamic Type, VoiceOver, contrast, RTL, focus and stable accessibility IDs are required throughout.

## Conversation experience

The centered grouped provider/model picker shows the selected model and persona. A quiet repository/branch row sits beneath it. The multiline composer supports document chips, dictation, explicit Send, red Stop, Plan/Act and reasoning controls appropriate to the selected model.

Keep stable assistant identity across reasoning, streaming and tool transitions. Preserve waiting/activity indication, timed reasoning disclosure, streaming caret, follow-scroll and manual reading position, plus return-to-latest. Tool pills expand into masked details with distinct success/failure/cancellation/approval states. Render selectable Markdown, code, tables, links, citations and source references.

Message actions: Copy, regenerate, continue, shorter, formal, explain, read aloud, details and content concern. Conversation actions: search, searchable history, pin, rename, archive, delete and fork. Compaction affects provider context while preserving the complete visible transcript. Explicit personas, project instructions, user-controlled memory and editable macros provide reusable context.

Each conversation owns provider/model/persona, repository/branch connection, composer/attachments, reading state, context, tools and staged draft. Switching chats/repositories preserves unsent work. Changing provider/repository cancels the current run and invalidates pending approvals. An edited repository with an outstanding draft requires explicit discard or a separate chat; reconnection is explicit.

Plan reads/searches/explains/proposes. Act additionally stages local edits and checkpoints. Remote writes always enter native review. `@` context references include files, folders, issues, PRs and documents; slash commands cover models, context, review, diffs, checkpoints and macros. Repository context maps are bounded and lexical. No embeddings runtime is introduced.

Context and usage are visible. Provider-reported input/output/reasoning counts remain separate from estimates. Cost is shown only with catalog or explicitly configured pricing. Comparisons/benchmarks are explicit cloud requests with tools disabled; no automatic comparison, fallback, classifier or billed retry occurs.

## Attachments and sharing

Support selectable text, Markdown, source, JSON and PDFs. A scanned PDF yields an unsupported-text explanation. Binary/images can be repository/release assets but never provider vision input. Native document access reads bytes into bounded memory without app-owned plaintext temporary copies.

The Share extension accepts text, HTTPS URLs and supported documents. It seals an encrypted inbox using a shared public encryption key; the private key and all service credentials remain in the main app's Keychain namespace. Export/backup is an authenticated encrypted bundle. Explicit response Copy uses a local-only clipboard item expiring after 60 seconds and masks detected credentials. Credentials have no copy action.

## Providers and adaptive reasoning

Presets: Apple, OpenAI, Anthropic, Gemini, DeepSeek, xAI, Mistral, OpenCode Go, OpenCode Zen, OpenRouter Free, OpenRouter, Groq, Qwen Code, Kimi Code, LongCat, custom HTTPS. Independent profiles allow multiple accounts/keys per provider. Catalog refresh is explicit, paginated and bounded; search and manual model IDs work without automatic selection changes.

Secrets are Keychain only. Show the destination disclosure before content leaves the device. Endpoint changes remove the key and consent. Model-specific privacy exceptions require additional native consent. Stop, provider removal, backgrounding and selection changes cancel affected work. HTTPS is mandatory, including custom endpoints; credentials never follow redirects.

Normalize Responses, Chat Completions, Anthropic Messages and Gemini streams: text, supplied reasoning summaries, native tool calls, usage, finish reasons and safe errors. Structured tools are preferred. The text-tool compatibility bridge is explicit and cannot execute quoted examples, unfinished arguments or reasoning content. Unsupported modalities/options fail explicitly.

Default budgets: 8,192 input / 4,096 output tokens, reduced for a model's known limits. Automatic reasoning adapts to task/latency within those budgets using catalog metadata and documented model families. Native effort/adaptive controls are used when supported. Unknown models receive answer-style guidance or retain their provider defaults; the UI does not imply hidden reasoning access. Manual verified protocol/capability/price overrides are possible. Continuation signatures/state remain bound to exact profile, endpoint and model.

Apple uses Foundation Models and system availability. The on-device system model requires Apple Intelligence eligibility/assets. PCC additionally requires OS 27, actual signed/provisioned entitlement, eligibility and quota. Reasoning is enabled only where Apple's capabilities support it; supplied summaries and actual usage are shown without fabricated internal thoughts. There is no silent Apple/cloud substitution or app model downloader.

## GitHub identity, permissions and tools

Use a dedicated Repo Manager GitHub App with device flow and expiring user tokens; no client secret or app private key is shipped. Fine-grained PAT is a secure native fallback. Support multiple accounts, pending authorization, slowdown, expiry, denial, cancellation, refresh rotation, revoked access, repository installation access and organization approval.

Scopes use account/connection identity plus stable repository ID and owner/name/branch. Detect renames/transfers rather than silently redirecting an old draft. Restored chats make no network requests. An old draft cannot attach to a fresh token without explicit reconnection. Tool discovery filters coarse role/mode/grants; GitHub enforces endpoint-specific fine-grained, installation, organization and product permissions on every read/write. Missing capability produces a safe unavailable/permission state.

The executable catalog in `Docs/tool-catalog.json` is the exact registered schema/risk/permission inventory. Required areas:

| Area | Surface |
| --- | --- |
| Repository browser | Information/favorites, branches/tags/tree/files/search, history/comparison, encrypted offline data |
| Files | List/read/ranges, write/replace/delete/move/upload, validated unified patch, hunk staging |
| Context | Code search, branch-specific bounded search, log/diff/info/branches, repository map and explicit coverage |
| Changes | Draft review, branches/tags, commits, clean merges/conflict comparison, open PR, forward revert, checkpoints |
| Issues | List/search/read/create/edit/close/reopen, comments, labels, assignees, milestones and issue-to-PR link context |
| Pull requests | Search/list/read/create/update, files/diffs, inline comments, draft/submit reviews, reviewers, threads, ready/close/reopen, allowed merge strategies |
| Collaboration | Discussions/comments, selected-repository linked Projects v2 items, scoped node validation |
| Actions | Workflows/runs/jobs/checks, bounded logs, dispatch/rerun/cancel, artifacts and deployment approval |
| Releases | Tags/release notes, create/edit/publish/delete, assets and bounded encrypted upload |
| Security | Credential scanning/redaction/history audit; available Dependabot/code/secret alert metadata and reviewed state updates |
| Administration | Create/fork, settings/collaborators/environments/webhooks, archive/visibility, rulesets/protection, transfer/deletion |
| Secrets | Native secure entry and reviewed repository/environment Actions/Dependabot create/replace/delete; agents see names/status only |
| General | Calculator/date/unit conversion, selected documents, consented web search/fetch, document indexing/lexical retrieval |

Web starts off and supports direct HTTPS, experimental DuckDuckGo, Brave, Tavily, Exa, SearXNG and custom search. Macros call the same services and cannot run shell or bypass reviews.

## Workspace and review protocol

Capture repository, branch, base commit and original snapshots; reads use the conversation's staged overlay. Staging sends no remote writes. Prepare an immutable review containing exact target, base, complete changes/operation and consequences. Revalidate account, connection, scope, permissions, draft revision and current remote state after approval and immediately before each write.

Publish blobs/tree/commit and a non-force ref update, preserve executable modes/history, and verify the resulting head. Symlinks/submodules are read-only metadata. On branch advancement retain the draft and offer bounded three-way comparison/restaging or explicit discard, then a fresh review. Supported merge commits preserve both parents and non-conflicting changes.

Reviews show account/repository/branch/entity/action, before/after or masked code diff, added/deleted files, modes/ancestry, binary sizes/hashes, visibility/permission/deployment consequences. Approval applies to one expiring immutable snapshot and is invalidated by changed targets/drafts/scopes/cancellation/remote state.

Deletion, transfer, visibility, permission/protection, secrets and deployment approval need native owner authentication and a specific confirmation. Deletion/transfer also require the full repository name. Secret review shows name/scope/create-replace-delete only, never an old or new value. Values are sealed to GitHub using pinned Sodium. Cancellation retains drafts. A lost write response is uncertain and must be inspected/reconciled before retry; 202 acceptance does not establish eventual completion.

| Limit | Default |
| --- | --- |
| Text file | 256 KiB |
| New repository attachment | 1 MiB |
| Staged draft | 30 changed files, 2 MiB combined before/after snapshots |
| File range | 200 lines |
| Tool steps | 25 GitHub turns; five other turns |
| Release asset/Actions artifact | 50 MiB per item, bounded encrypted chunks |
| Agent request body | 1 MiB |
| Provider stream | 8 MiB, bounded parser/consumer buffers |

Every bounded read/search/log/map displays truncation/coverage. Indexed code search identifies default-branch coverage; selected-branch search uses a bounded tree/blob scan. No clone or whole-history claim is made.

## Apple-native voice

Use SpeechAnalyzer/SpeechTranscriber on supported platforms/locales and an on-device-only SFSpeechRecognizer fallback; AVSpeechSynthesizer reads responses. System-managed speech assets are permitted. No Whisper/neural VAD is imported.

Tap/hold dictation produces partial/final composer text, supports stop/language availability and retains the prior draft. Read aloud exposes voice/rate/Stop. Continuous conversation states: listening, transcribing, responding, speaking, paused and approval. A minimized session survives navigation with its captured conversation identity. Apple audio processing, bounded silence detection, audio routes, interruptions/headset changes and playback interruption determine turn boundaries.

Audio stays in memory; only transcript text reaches a selected provider. Background/lock cancels capture and releases buffers. Voice pauses for native reviews and cannot grant consequential approval. Physical-device microphone, audio-route and interruption verification remains a release requirement.

## External-agent API

Opt-in HTTPS, port 11435, authenticated discovery/models and scoped version 1 sessions/tools/runs/events/operations. Compatibility: `/v1/models`, `/v1/chat/completions`, `/v1/responses`, `/v1/messages`, `/api/tags`, `/api/show`, `/api/version`, `/api/chat`, `/api/generate`; `/api/ps` reports no local runtimes. Apple system services are distinct from imported/local runtime inventory.

Compatibility routes return client-owned tools to the caller. Agent-run routes execute granted built-in tools through the same review coordinator. Native UI grants repository/provider/tool scope; external clients cannot read existing chats, broaden scope or approve with flags/routes. Requests are typed/bounded; safe errors, cancellation, SSE/NDJSON, ownership, idempotency and explicit unsupported options are required. Listener stops on inactivity/background/lock/quit. No VPN or continuous iOS background server is provided.

## Storage, sync and security

Credentials/refresh/client tokens: separate nonsynchronizing Keychain items. Device encryption/TLS keys: device-only unlocked Keychain, Secure Enclave for compatible TLS keys. Conversations/documents/code/drafts/checkpoints/metadata/receipts: authenticated encrypted files. Search: memory only. Sync: ciphertext only. Export: Argon2id-derived protection and authenticated encryption, excluding credentials/live approvals.

AES-256-GCM uses fresh nonces, authenticated version/object IDs, opaque names, atomic writes and tamper detection. Keychain failures block; no UserDefaults/file/environment/plaintext fallback. Device-only keys do not migrate. Existing ciphertext survives missing keys; recovery cannot overwrite it with a new empty vault.

History sync is opt-in and uses a separate synchronizable Keychain key. It waits on missing keys and never uploads plaintext. Immutable messages, deletion tombstones and conflict copies preserve divergent transcripts. Credentials/cache/drafts/reviews/grants remain local; incoming chats need local provider/repository authorization.

TLS for every app-controlled network request; host/IP-valid server certificates, explicit public trust/fingerprint pairing, distinct client credentials/revocation/limits. Validate paths/refs/schema/destinations and ownership. Files/issues/comments/web/logs are untrusted data and cannot authorize actions. Block SSRF, traversal, credential URLs and unsafe redirects. Imported instructions/code/macros/workflows do not execute automatically. Do not log secrets, prompts, outputs, documents, raw upstream errors or media. Cover inactive UI and release clear caches/audio. Wipe only the independent app namespaces.

## Acceptance and delivery

Deliver app/Core/UI/Share sources, XcodeGen config, local Git repo, full specification, setup/architecture/privacy, tool schemas/catalog, OpenAPI, provenance/licenses, functional evidence and a dated dedicated security report.

Functional gates: Simulator, generic iOS and Catalyst builds; chat keyboard/draft/scroll/reasoning/tool/Stop/accessibility parity; every provider format with split Unicode/usage/errors/cancel/tools; OAuth flow/rotation/revocation; scoped reads/overlay; no staging writes; mode/history preservation and stale-review rejection; management success/failure; native destructive/secret policy; voice lifecycle; encrypted sync/conflicts/missing keys; agent ownership/grants/review enforcement.

After implementation and available functional QA, start a separately recorded security round: written threat model; plaintext canaries across containers/temp/defaults/export/sync/logs; missing/locked/deleted keys, nonce/corruption/backup/wipe; dependencies/binaries/licenses/signing/privacy settings; TLS/revocation/replay/scope/SSRF; prompt injection; review bypass/expiry/races; ambiguous destructive writes/secrets/deployments; physical locking/microphone/cover. Fix findings and rerun affected checks. No unresolved critical/high findings and complete functional/platform gates are required for a passing release status.

Live tests are opt-in with explicit credentials and a disposable repository. CI uses fixtures and makes no billed/model/GitHub mutation calls. Create the authorized ASC record with English (US) and upload a signed, gate-approved build to TestFlight. Publishing Git or releasing to the App Store is outside this implementation.
