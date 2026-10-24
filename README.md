# Repo Manager

A free, MIT-licensed native GitHub workspace for iPhone, iPad and Apple silicon Macs through Mac Catalyst. Chat with a selected model, inspect repository context, stage changes locally, and review GitHub changes before publication.

Complete MIT source is public at [Mesutcydev/RepoManager](https://github.com/Mesutcydev/RepoManager). This source includes official **Continue with ChatGPT**, enabled in Debug, TestFlight and Release. Eligible Plus and Pro users can authorize their plan for eligible AI requests without an API key. ChatGPT sign-in and eligible plan usage remain free in Repo Manager. The external policy classification of optional paid API-provider features is recorded in [MONETIZATION.md](Docs/MONETIZATION.md); no commercial-access approval is claimed. [OpenAI quickstart](https://developers.openai.com/siwc/quickstart).

## Open-source and App Store editions

The complete app, Share extension, core/UI packages, source assets, build configuration and tests are public under the [MIT license](LICENSE), with third-party notices preserved. The exact archived source for **1.0 (24)** is available at [v1.0-build.24](https://github.com/Mesutcydev/RepoManager/tree/v1.0-build.24). The default branch includes that app code and subsequent documentation updates.

The MIT source can be built and modified under its license. Optional Pro is a purchase in the official App Store binary, not a separate source-code license. ChatGPT sign-in and eligible plan usage remain free in Repo Manager. Forks use their own signing identifiers, GitHub App and service accounts. API usage and ChatGPT eligibility remain governed by the selected service.

## Build

Requires macOS, Xcode 27.1, Swift 6 and XcodeGen 2.44 or later. Minimum iOS/iPadOS and Mac Catalyst targets are 26.

```sh
git clone https://github.com/Mesutcydev/RepoManager.git
cd RepoManager
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
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

Optional $9.99 one-time Pro unlocks API-key providers and custom compatible HTTPS endpoints. ChatGPT, Apple Intelligence on supported devices and the GitHub workspace remain included. Pro is enabled in the release candidate; the App Store product is configured, while physical-device Sandbox acceptance and public review remain pending. Provider API usage is billed separately. See [the monetization plan](Docs/MONETIZATION.md).

## Documentation

- [Setup](SETUP.md), [architecture](ARCHITECTURE.md), [contributing](CONTRIBUTING.md).
- [ChatGPT integration](Docs/CHATGPT_SIGN_IN.md), [free release](Docs/OPEN_SOURCE_RELEASE.md).
- [Privacy](PRIVACY.md), [third-party notices](THIRD_PARTY_NOTICES.md), [MIT license](LICENSE).
- [Tools](Docs/TOOL_CATALOG.md), [external API](Docs/openapi.json), [reasoning](Docs/REASONING.md).

Automated tests use synthetic credentials and make no billed AI requests or live GitHub mutations. Live ChatGPT authorization/inference and signed-device checks remain distinct release checks. Internal QA logs, screenshots and account/store evidence are excluded from this public snapshot.
