# Contributing

Repo Manager's complete MIT source is public at [Mesutcydev/RepoManager](https://github.com/Mesutcydev/RepoManager). The current distribution is free. Build 24 enables the optional $9.99 one-time Pro unlock only for API-key providers and custom HTTPS endpoints, with ChatGPT always included; see [Docs/MONETIZATION.md](Docs/MONETIZATION.md). Use Xcode 27.1, Swift 6 and XcodeGen 2.44 or later. Generate from `project.yml`, configure your own signing identifiers for device builds, and follow [SETUP.md](SETUP.md).

Run `swift test --package-path Packages/RepoManagerCore` and `python3 scripts/validate_project.py` before submitting changes. Build iOS Simulator and Mac Catalyst for native changes. Tests use synthetic credentials; describe separate live-service checks accurately.

Preserve encrypted local storage, explicit destination consent, account credential boundaries, and native approval of GitHub mutations. Do not commit tokens, signing keys, browser authorization URLs, account screenshots or local QA evidence. Keep source/asset attribution and third-party notices.

For ChatGPT changes, follow the official public OAuth/Responses contract in [Docs/CHATGPT_SIGN_IN.md](Docs/CHATGPT_SIGN_IN.md). Add meaningful coverage for authentication, refresh, stream failure or tool execution affected by the change. Do not reuse Codex client IDs or undocumented ChatGPT endpoints.
