# Capabilities and entitlements

Reviewed 11 October 2026 against installed Xcode 27 SDKs and Apple's primary documentation. These files belong only to Repo Manager; no reference entitlement or identifier was reused.

## Enabled or configured

| Capability | Target | Purpose and guard |
| --- | --- | --- |
| Private Cloud Compute | Main app, iOS/Catalyst | User-requested OS 27 Apple provider; actual signed entitlement, profile, eligibility and quota checks. A grant must be provisioned on the new App ID. |
| CloudKit | Main app | Explicit encrypted conversation-history sync in `iCloud.com.mesutcydev.repomanager`; missing key/capability blocks sync. |
| App Groups | Main app and Share extension | `group.com.mesutcydev.repomanager`; public inbox key and ciphertext only. |
| Keychain | Main app's default private access group | Tokens, vault/inbox keys and client credentials. No shared credential access-group entitlement. History key alone becomes synchronizable after sync opt-in. |
| BGAppRefresh / BGProcessing | iPhone/iPad | Opt-in bounded metadata refresh and encrypted history sync; `fetch`/`processing` Info.plist modes and registered identifiers, not an entitlement to permanent execution. |
| Mac App Sandbox / Hardened Runtime | Catalyst app/extension | Scoped access and hardened execution; target-specific files/settings. |
| Outgoing network client | Catalyst main app | HTTPS providers, GitHub and consented public web. |
| Incoming network server | Catalyst main app | Explicit authenticated HTTPS listener; stops while inactive/locked. |
| Audio input / microphone | Catalyst main app | User-requested Apple speech only; no background capture mode. |
| User-selected files read/write | Catalyst main app | Native supported document imports and encrypted exports via system pickers. |

PCC: [Apple entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute), [Foundation Models](https://developer.apple.com/foundation-models-framework/). Background scheduling: [BGProcessing networking](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtaskrequest/requiresnetworkconnectivity). Mac: [App Sandbox configuration](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox). Private Keychain: [access-group sharing](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps), [device-only accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly).

## Native permissions

`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSFaceIDUsageDescription` and `NSLocalNetworkUsageDescription` explain requests when used. LocalAuthentication uses owner authentication for consequential changes. Speech assets/transcription stay under Apple's system management. These permission strings are distinct from entitlements. [Face ID/Touch ID](https://developer.apple.com/documentation/LocalAuthentication/logging-a-user-into-your-app-with-face-id-or-touch-id), [Apple Speech](https://developer.apple.com/documentation/speech/).

No camera permission, local-model runtime entitlement, private CoreAI/PCC access key, remote-control companion, VPN/proxy entitlement or arbitrary ATS exception is included. Share has no networking/microphone/PCC/CloudKit credential capability.

## Considered additions

| Option | Decision |
| --- | --- |
| APNs push / remote notification | Useful for future GitHub event notifications, but requires a trusted backend/event delivery design. Current activity is explicit refresh and bounded BGTasks; no unused push entitlement is requested. |
| Background URLSession | Useful for file transfers, but system upload tasks need files. Sensitive asset uploads remain foreground bounded streams from encrypted chunks; no plaintext background upload file is created. |
| Background audio | Continuous background microphone is outside the requested networking scope. Voice stops when backgrounded. |
| Network Extension | VPN/proxy/filter extension would add a separate security and entitlement scope; user clarified background networking. |
| iCloud key-value store | Sensitive settings are encrypted; unused KVS entitlement was removed. |
| Shared credential Keychain group | Unnecessary. The extension encrypts with a public key and cannot read main-app credentials. |
| Secure Enclave for AES records | Secure Enclave cannot directly store/export an AES record key. Records use a device-only unlocked Keychain key; compatible EC TLS signing keys prefer Secure Enclave. |
| App Attest / DeviceCheck | Potential future remote-service abuse protection. There is no app-owned remote backend needing attestation in this build. |
| Siri / Shortcuts / App Intents | Potential reusable read/search workflows; consequential writes would still need native immutable reviews. No extra privilege is added merely to expose commands. |

## Background contract

Background networking starts off. The encrypted setting opts into refreshing at most three conversation-selected scopes with the current connection identity and optional encrypted history. The system chooses when to run. Workers require available protected data and stop on expiration, foreground or device locking. No model request, mutation tool, voice capture or server is started by a background task.

The main app does not promise indefinite background execution on iOS. Catalyst uses the conservative inactive-stop listener policy; widening it to an unlocked but unfocused session would require physical lock verification first.

## Provisioning and verification

Source entitlements configure requested capabilities; they are not proof of an Apple provisioning grant. Release inspection must compare signed app/extension entitlements to their distribution profiles, inspect CloudKit production schema and confirm the new main App ID's PCC grant. Simulator builds cannot establish PCC or device-only Keychain/lock behavior. Those checks stay pending without a device.
