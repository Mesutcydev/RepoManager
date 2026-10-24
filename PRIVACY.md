# Privacy

24 October 2026 · Repo Manager 1.0

Repo Manager has no developer-operated account service, analytics collector, advertising SDK or crash-upload backend. It processes repository and conversation data locally and sends only explicitly requested content to the selected service. A configured upstream provider and GitHub apply their own retention and privacy terms.

## Data and destinations

| Data | Processing and persistence |
| --- | --- |
| API/GitHub/refresh/client credentials | Separate device-only, nonsynchronizing, unlocked Keychain records. No clipboard, logs, export or file/defaults fallback. |
| Conversation, repository contents, docs, drafts, checkpoints, settings and receipts | AES-256-GCM encrypted local records, opaque names and protected atomic writes; plaintext only in transient processing/display memory. |
| AI requests | Explicit selected provider/model/endpoint after disclosure. Repository/tool/document text is bounded and detected credentials are masked. No automatic provider switch or billed retry. |
| ChatGPT sign-in and plan usage | External Safari or the selected system browser signs in at auth.openai.com. Verified account subject, issued registration, and optional name/email identify independent connections. OAuth access, refresh and ID tokens stay in device-only Keychain; host ID is an opaque installation UUID. Eligible requests go to api.openai.com/v1/responses with store disabled. This does not grant access to ChatGPT conversations. |
| Apple system model | Apple-managed on-device Foundation Models, when available. No imported/downloaded app runtime. |
| Apple PCC | User-enabled, entitlement/device/quota-gated Apple service. Transcript/context sent under Apple's PCC protection; audio is not sent. |
| GitHub | Explicit account/repository API reads and native-reviewed writes; installation/role/organization policy is enforced by GitHub. |
| Web search/fetch | Off until destination configuration/consent; requests go to the chosen HTTPS search service or direct public URL. |
| Microphone | Audio buffers in memory for Apple-native transcription/turn detection. Background/lock/Stop ends capture. Only transcript text is added to AI context. |
| Read aloud | Apple AVSpeechSynthesizer; no app-operated speech service. |
| Search/knowledge | Lexical index in memory, rebuilt from encrypted documents. No plaintext SQLite/WAL or embeddings model. |
| Optional iCloud history | Encrypt before CloudKit upload with a separate explicitly enabled synchronizable Keychain key. Repository caches/drafts/editor drafts/credentials/reviews/client grants remain device-local. Missing keys block sync. |
| Share inbox | Public-key sealed ciphertext in the dedicated App Group. Extension receives no private key or service credentials. |
| Exports/backups | Encrypted `.rmbundle`, Argon2id passphrase protection, excluding credentials and live approvals. Reconnection/fresh review required after import. |
| Copy | User-triggered response text, credential-masked, local-only clipboard, 60-second expiry. |
| External agents | Explicit HTTPS client credentials/grants; no default existing chat history or unrestricted repository access. Client-owned compatibility tool calls are returned to that client. |
| Optional Pro purchase | The optional one-time Pro unlock covers API-key providers and custom HTTPS endpoints; ChatGPT does not require it. Apple StoreKit handles payment and returns locally verified purchase entitlements. Repo Manager has no developer payment backend and does not receive payment-card details. No purchase token or receipt is included in portable vault exports. |

Detected credentials are masked, but detection is a bounded aid rather than proof a document contains no secrets. Users decide which repository/documents to disclose. The app never asks a model to store or manage secret values; Actions/Dependabot secrets use native secure input and GitHub sealed-box encryption.

## Background and access

Background networking is opt-in and limited to current-scope metadata and optional encrypted history. It cannot run AI or execute remote mutations. Background/lock stops microphone capture and the local HTTPS agent server, locks the workspace and releases decrypted caches and conversation presentation state. The app has no separate app-switcher cover window or inactive overlay. Native authenticated removal wipes only Repo Manager records, keys and inbox.

ChatGPT sign-in uses a short-lived HTTP callback bound exclusively to `127.0.0.1`. It accepts only the pending, state-validated OAuth result. The final browser-return URL contains a random marker, with no authorization code or token. An explicitly owned, unconsumed sign-in attempt and its callback listener can remain in memory while switching to the browser or passkey/password app. Token exchange and credential application wait for foreground workspace restoration. The attempt expires after ten minutes; completion, explicit cancellation, expiration or app termination closes it. A finite OS background grace period supports a quick callback; if iOS suspends the process during a longer sign-in, return to Repo Manager to resume. This does not promise survival after process termination. ChatGPT sign-out attempts remote refresh-session revocation, then clears local tokens; if remote revocation cannot be confirmed, the app explains how to disconnect in ChatGPT settings. Credentials and active ChatGPT account mappings are not restored from portable backups.

Device-only credentials/vault keys do not migrate to another device through backup. Missing keys leave ciphertext intact. Loss recovery requires an encrypted portable backup or explicit authenticated data removal, never silent overwrite with a new empty vault.

Provider retention is destination/model specific and can change. OpenCode contributor/free/trial models receive an extra consent notice. There is no blanket zero-retention promise for all cloud APIs. Review [OpenCode Go](https://docs.opencode.ai/docs/go/) and [Zen](https://docs.opencode.ai/docs/zen/) or the selected provider's current terms.

## App Store disclosures

Permission prompts explain microphone, speech, Face ID and local networking. No camera permission is requested. Privacy manifests list applicable required-reason APIs only; no tracking domains are declared. App Store nutrition labels must describe **the actual released behavior**, including explicitly selected third-party AI/cloud processing. Do not assume that the absence of a developer backend automatically means no data collection by connected services.

The reviewed nine-category App Store privacy declaration was published on 24 October 2026. Physical-device purchase, live-service and device-lock/audio acceptance remain separate release checks. No personal information or credentials are requested in chat for setup.
