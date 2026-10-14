# Setup

## Toolchain and build

Use Xcode 27 and Swift 6. The minimum OS targets remain 26. Run XcodeGen from this repository; `project.yml` is the source of truth. Generated projects, packages downloaded by SwiftPM, derived data, archives and signing files are excluded from Git.

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -project RepoManager.xcodeproj -scheme RepoManager
xcodebuild -project RepoManager.xcodeproj -scheme RepoManager \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RepoManager.xcodeproj -scheme RepoManager \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RepoManager.xcodeproj -scheme RepoManager \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build
```

Swift-Sodium is pinned to 0.11.0. Its bundled Apple XCFramework is used by the Apple targets. Resolve the exact revision in `Docs/DEPENDENCY_PROVENANCE.json`; do not replace it with an unverified binary.

## Signing and Apple capabilities

Configured team: `PUH4GMFV56`. Provision these independent identifiers on that team:

| Identifier | Purpose |
| --- | --- |
| `com.mesutcydev.repomanager` | Main app |
| `com.mesutcydev.repomanager.share` | Share extension |
| `group.com.mesutcydev.repomanager` | Encrypted inbox and public inbox key only |
| `iCloud.com.mesutcydev.repomanager` | Optional encrypted history |

Enable App Groups for the app and extension. Enable CloudKit and the granted Private Cloud Compute capability on the **new main App ID** and regenerate its provisioning profile. An entitlement granted to a different app identifier does not provision Repo Manager. The Share extension receives neither PCC nor CloudKit nor shared credential Keychain access.

The runtime checks the actual signed PCC entitlement and device eligibility. OS 26 exposes the Apple system model if available; OS 27 additionally exposes PCC and system-supported reasoning. A simulator, unsupported language, missing Apple Intelligence assets, device ineligibility, missing entitlement or exhausted PCC quota produces an availability explanation. There is no silent cloud substitute.

For CloudKit, create an `RMHistory` record type in the private database with `ciphertext` (Bytes) and `version` (Int64). Enable queries for the record type, deploy the schema to production for TestFlight, and verify it with a real signed device. Record names are hashes; titles, messages and deletions are encrypted before upload. Enable sync only from the app. It creates a separate synchronizable history key after verifying no remote ciphertext would be orphaned.

## GitHub App pairing

The dedicated **[Repo Manager by Mesutcydev GitHub App](https://github.com/apps/repo-manager-by-mesutcydev)** is registered with device flow and expiring user access tokens enabled. Its public client ID and slug are bundled from `project.yml`; users do not enter a client ID. See [registration settings and verification](Docs/GITHUB_APP_SETUP.md). Device authorization and refresh use GitHub's HTTPS endpoints without embedding a client secret. Do not reuse OnDeviceMax/SiteAgent registration or copy its credentials.

Install the app only on the repositories to be managed. Grant permissions needed by enabled features, starting with metadata and contents read. Write workflows need contents write; issues/PRs, Actions, discussions, deployments, environments, secrets, alerts and repository administration each need their corresponding GitHub App permissions. Projects v2 may require the available organization/user project permissions as well as repository linkage. Organization approval, repository roles, plan availability and endpoint-specific permissions can still reject an action. [GitHub App permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps), [token refresh](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens).

Fine-grained PAT fallback accepts `github_pat_` tokens entered through the native secure field. Select only the necessary repositories and permissions and respect organization approval/expiry. Classic PATs are excluded. Reconnection creates a new connection identity; an old staged draft requires explicit reconnection and a fresh review.

The app ships no app private key, client secret, installation token generator or account token. Pairing requires a valid dedicated Client ID. Restoring conversations makes no network requests.

## Provider setup

For local Debug builds, choose **Add provider → ChatGPT**, review and enable the OpenAI destination disclosure, and select **Continue with ChatGPT**. An eligible Plus or Pro account can authorize ChatGPT plan usage without an API key. Each saved connection keeps its own account/workspace registration. Sign-out retains that registration and removes its tokens; removing the provider forgets it. See [ChatGPT sign-in](Docs/CHATGPT_SIGN_IN.md) for the public-release configuration and live verification steps.

The user-authorized on-device beta uses the `RepoManagerTestFlight` scheme and `TestFlight` configuration, with ChatGPT enabled and Release optimization. The ordinary public `Release` remains gated until source publication. TestFlight upload, public source publication and App Store release are separate actions.

Create a profile, review the HTTPS destination disclosure, enter an API key in the secure field, and explicitly refresh the catalog or enter a model ID. Multiple profiles for the same provider are independent. Changing an endpoint removes its saved credential and model-specific consent. No plaintext `.env` or file credential configuration is supported.

OpenCode Go and Zen select the documented endpoint/protocol for each model; model settings can supply verified limits, pricing and reasoning capabilities. Contributor/free/trial models have an additional native model privacy disclosure. Catalog availability and prices can change; refresh explicitly. Unknown prices and usage remain unknown.

Web tools start off. Choose direct URLs or a search provider (experimental DuckDuckGo, Brave, Tavily, Exa, SearXNG or custom HTTPS), review its destination, and enter its credential in the secure native field when needed. Private/LAN destinations, credential-bearing URLs and unsafe redirects are rejected.

## External clients

Enable the HTTPS server only when needed. Configure the reachable local hostname or IPv4 interface address before generating a certificate. Export the **public** trust certificate, verify its SHA-256 fingerprint in person, and configure the client to trust that certificate while keeping hostname/IP verification enabled. A changed host or expired certificate requires new trust pairing. Never use an insecure TLS flag.

Create a distinct native client grant with explicit provider profiles, optional selected repository, and a list of built-in tools. Repository creation and forking require account/target grants outside this repository-scoped API contract, so those workflows remain in native screens and app chat. The one-time credential is displayed for manual entry only and is never copied to clipboard. Do not paste it into chat, scripts committed to Git, URLs or logs. Store it in the client's protected secret storage.

Models are addressed as `profile-UUID/model-ID`. See `Docs/openapi.json` for routes. Compatibility tools remain client-owned; agent routes execute only granted app tools. All remote mutations return pending native reviews. No API approval route exists. Revocation stops app-managed runs; inactive/lock/quit stops the listener.

## Backup and recovery

Export an `.rmbundle` using a passphrase of at least 12 UTF-8 bytes. The bundle contains authenticated ciphertext protected with an Argon2id-derived key and excludes credentials and live approvals. Keep the passphrase separately. Import preserves drafts but remaps profile/conversation identities, clears disclosure consent, disables sync/web and invalidates GitHub connection identities.

A missing vault key never replaces the encrypted files with an empty vault. Unlock Keychain or recover from an encrypted backup. Explicit native authenticated removal is the recovery path when the device-only key is irretrievably lost. Device vault keys and credentials do not migrate through backups.

## Validation and release

UI tests use `--ui-fixtures`, `--onboarding-fixtures` and `--reduced-motion-fixtures` in Debug. Do not use those modes to describe a live GitHub or provider test. Live tests require explicit local credential entry and a disposable repository; CI never bills a model or mutates GitHub.

Use the release gate after functional QA and the dedicated security round. App Store Connect language is English (US). App name is Repo Manager. Local repository publication, App Store release and tester invitations are separate actions from the authorized TestFlight upload.
