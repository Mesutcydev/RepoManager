# Repo Manager

A free, MIT-licensed native GitHub workspace for iPhone, iPad and Apple silicon Macs through Mac Catalyst. Chat with a selected model, inspect repository context, stage changes locally, and review GitHub changes before publication.

This source snapshot is prepared for public release. It includes official **Continue with ChatGPT** for local/personal Debug builds and the user-authorized TestFlight beta. Eligible Plus and Pro users can authorize their plan for eligible AI requests without an API key. Public Release enablement requires publishing complete source and configuring the actual repository URL. [OpenAI quickstart](https://developers.openai.com/siwc/quickstart).

## Build

Requires macOS, Xcode 27, Swift 6 and XcodeGen 2.44 or later. Minimum iOS/iPadOS and Mac Catalyst targets are 26.

```sh
cd RepoManager
xcodegen generate
open RepoManager.xcodeproj
```

Simulator builds do not require the original developer's signing identity. For devices/distribution, configure your own team, bundle identifiers, App Group and CloudKit container in [SETUP.md](SETUP.md). Forks should use their own GitHub App. No developer API key, client secret or signing key is included.

```sh
swift test --package-path Packages/RepoManagerCore
python3 scripts/validate_project.py
xcodebuild -project RepoManager.xcodeproj -scheme RepoManager \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Features

- Official ChatGPT sign-in, separate account/workspace registrations, protected token refresh and visible plan-usage controls.
- API-key profiles for OpenAI and other supported providers, custom HTTPS endpoints and Apple Intelligence.
- Repository/branch context, encrypted offline data, local staged changes and native review of remote mutations.
- Apple-native voice, optional encrypted history sync and an opt-in authenticated local HTTPS agent API.

The current app is free. API-key usage is billed by the selected provider. Authorized ChatGPT requests consume the user's eligible allowance or permitted credits; manage access and limits in ChatGPT settings.

The owner plans an optional one-time Pro unlock for API-provider/custom-endpoint support while keeping ChatGPT connection and Apple Intelligence in the free core. No purchase or paywall is implemented in this snapshot. OpenAI confirmation for that freemium model is pending; MIT source publication does not establish commercial access approval. See [the monetization plan](Docs/MONETIZATION.md).

## Documentation

- [Setup](SETUP.md), [architecture](ARCHITECTURE.md), [contributing](CONTRIBUTING.md).
- [ChatGPT integration](Docs/CHATGPT_SIGN_IN.md), [free release](Docs/OPEN_SOURCE_RELEASE.md).
- [Privacy](PRIVACY.md), [third-party notices](THIRD_PARTY_NOTICES.md), [MIT license](LICENSE).
- [Tools](Docs/TOOL_CATALOG.md), [external API](Docs/openapi.json), [reasoning](Docs/REASONING.md).

Automated tests use synthetic credentials and make no billed AI requests or live GitHub mutations. Live ChatGPT authorization/inference and signed-device checks remain distinct release checks. Internal QA logs, screenshots and account/store evidence are excluded from this public snapshot.
