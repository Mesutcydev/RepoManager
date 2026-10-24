# Official Sign in with ChatGPT

14 October 2026. Native implementation for Repo Manager's free local open-source release.

OpenAI documents ChatGPT plan usage for local open-source tools and personal projects, while commercial/private integrations require selected access. Eligible Plus and Pro users can authorize eligible AI requests without configuring an API key. Identity sign-in alone does not grant plan usage. [Quickstart](https://developers.openai.com/siwc/quickstart), [availability and host identity](https://developers.openai.com/siwc/token-sharing-open-source).

## Try the local build

1. Generate with `xcodegen generate` and build Debug on iPhone, iPad or Mac Catalyst.
2. Open **Providers → Add provider → ChatGPT**. Label the connection, review the destination, and enable **Allow requests to OpenAI**.
3. Choose **Continue with ChatGPT**. External Safari (or the selected system browser) opens OpenAI authorization. Select an eligible account/workspace and authorize plan usage. Switching to a passkey/password app retains the pending attempt; return to Repo Manager after approval to finish. **Open Safari** reopens the same pending attempt, and **Cancel sign-in** ends it explicitly.
4. The app verifies the account before activating the connection and fetches its available models. Select one in the conversation's Model picker.
5. Send a small explicit test prompt. Sign-in/model discovery alone is not proof of inference access; the request must reach `response.completed`.
6. Use **Manage usage** beside the composer or in account settings to review app usage and limits.

The first authorized plan connection shows a one-time confirmation. Add another ChatGPT provider to keep another account or workspace separate. Matching emails never merge registrations; labels display a stable registration suffix.

## Authorization and storage

`ChatGPTConnectionStore` owns tokens. `ChatGPTSignInSession` opens the external system browser, independently of the account sheet. `ChatGPTLoopbackListener` binds only IPv4 loopback on a temporary port and limits request sizes/connections. Background locking retains only the explicitly owned, unconsumed OAuth attempt and the listener; token exchange waits for foreground workspace restoration. A finite OS background grace period allows a quick callback to return to the app. If iOS suspends the process during a longer sign-in, return to Repo Manager to resume; the continuation is memory-only and expires after ten minutes. Completion, explicit cancellation, expiration or app termination closes it. This does not promise survival after iOS terminates the app.

Initial authorization uses `client_id=dynamic_agent_client`, `agent_name_hint=Repo Manager`, a persisted installation `urn:uuid:…` host ID, fresh state/nonce, and PKCE S256. The callback path stays `/auth/callback`; the exact URI/port is reused in exchange. The issued `oaiapp_…` client ID is saved before exchange and reused on subsequent sign-ins and refreshes. No client secret or partner API key is embedded. [Registration contract](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).

Scopes are `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, for resource `https://api.openai.com/v1`. The app checks returned scopes. A connected identity without direct plan permission cannot discover models or run inference; settings can repeat consent explicitly.

ID tokens are verified against OpenAI's published JWKS using native RSA or CryptoKit P-256 signature verification. Signature, supported algorithm, key ID, issuer, audience, expiry, issued time and authorization nonce must validate. Returning sign-in/refresh cannot replace the selected account with another subject. Tokens stay in nonsynchronizing, device-only Keychain. Refreshes for a registration are serialized, and replacement refresh tokens are saved before reuse. [Session requirements](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions).

The loopback response redirects to the app's browser-return scheme with only a random marker. OAuth codes/tokens are never forwarded to that URL. A reset browser response socket does not discard an already validated callback. There is no embedded credential-entry page, account backend, Codex client-ID reuse or ChatGPT backend-api access.

## Models, tools and responses

Models come from the selected account's `GET https://api.openai.com/v1/models`: its `models` array, `visibility: list`, `display_name`, and `slug`. Server order is preserved, manual model entry is disabled, and the catalog refreshes on connection/reconnection. Each provider's model picker selects its own registration. [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).

Inference uses `POST https://api.openai.com/v1/responses`, OAuth Bearer authorization, `store: false`, `stream: true`, an `input` array and instructions. It omits unsupported `max_output_tokens`, places local function tools in the `repo_manager` namespace, and preserves that namespace in history. The app bounds context, stream size and local tool steps; GitHub mutations still need native review. [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).

Tools are released to the run coordinator only after completed inference. Failed/incomplete responses, explicit errors, interrupted streams and `[DONE]` without `response.completed` cannot succeed or execute pending tools. HTTP status, structured error code/parameter, body shape and request ID are retained as safe diagnostics; raw service messages are not shown/logged. Usage-limit failures make **Manage usage** the primary error action. There is no automatic inference retry or billing/provider fallback. [Recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery), [usage UX](https://developers.openai.com/siwc/ui-ux-guidelines).

## Release configuration

Build 24 enables `REPO_MANAGER_CHATGPT_PLAN_USAGE_ENABLED=YES` and optional Pro in Debug, TestFlight and Release. ChatGPT authentication is exempt from the Pro access gate. The app is MIT open source and declares its public repository in `REPO_MANAGER_OPEN_SOURCE_URL`. Regenerate the project after configuration changes.

The prebuild validator requires a declared public-source URL and license for enabled Release ChatGPT. It warns when optional Pro is enabled without a verified commercial-access decision. `REPO_MANAGER_CHATGPT_MONETIZATION_CLEARED` remains NO; no approval is claimed. OpenAI's documentation directs paid or remotely hosted apps to request access, but does not explicitly classify free ChatGPT inside an app with paid API-provider features. The official form confirmed receipt on 14 October 2026; receipt is not approval. Review this uncertainty before public submission. See [MONETIZATION.md](MONETIZATION.md) and [official availability guidance](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt).

## Verification status

Automated coverage uses synthetic credentials, real ES256/RS256 signatures, HTTP fixtures, and a local loopback listener. Native screen tests check disclosure and API-key-free sign-in without real authorization. The development workspace retains evidence in `Docs/QA/CHATGPT_SIGN_IN.md`; internal QA files are excluded from the public-source snapshot.

Live eligible-account consent, completed inference, real token renewal/revocation, and system-browser behavior on physical iPhone/iPad and Mac Catalyst remain release checks. Enter credentials only in OpenAI's browser page on the device; never paste tokens into chat, logs or issues.
