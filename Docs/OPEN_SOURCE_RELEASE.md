# Free open-source release preparation

24 October 2026. The MIT source repository is public. This candidate adds the refined paywall and optional **$9.99 one-time Pro** unlock for API-key providers and custom HTTPS endpoints. ChatGPT sign-in and eligible plan usage always remain free in Repo Manager, alongside Apple Intelligence on supported devices and the GitHub workspace. The App Store product is configured; physical-device acceptance and public review remain pending. See [MONETIZATION.md](MONETIZATION.md).

## Prepared locally

- Preserve the existing MIT license, upstream copyright notices, Swift-Sodium/libsodium licenses and bundled third-party notices.
- Include the complete native app, Share extension, core/UI packages, source assets, package pins, build configuration, source validators and tests.
- Support official **Continue with ChatGPT**, independently of API-key providers and GitHub sign-in.
- Explain that the app is free, API-key providers bill their own usage, and eligible ChatGPT requests use the authorized user's plan.
- Generate the reviewable public-source ZIP with `python3 scripts/prepare_open_source.py`. It contains build sources, public documentation, a public README and SHA-256 manifest. It excludes Git history, caches, signing files, personal QA logs/screenshots, TestFlight receipts and App Store evidence.

## Published source

Complete source is published at [Mesutcydev/RepoManager](https://github.com/Mesutcydev/RepoManager), with a fresh history containing only the reviewed public snapshot. The original development workspace's private QA files, account evidence and existing Git state were preserved and are not part of that history. Source publication does not change App Store pricing or submit an App Store release.

The source ZIP's hashes and license/asset notices were checked, and the extracted source built for iOS Simulator with signing disabled. Anonymous download verifies the published source against that clean snapshot. Forks should configure their own signing identities and GitHub App.

`REPO_MANAGER_OPEN_SOURCE_URL` points to the public repository. The current build 24 source package is prepared locally and must be synchronized to that repository before public release; the older published snapshot does not establish publication of these changes. Both ChatGPT and optional Pro are enabled in Debug, TestFlight and Release. Debug fixtures are excluded from production binaries.

Complete live checks in [the integration guide](CHATGPT_SIGN_IN.md) and physical-device Sandbox checks before public submission. App download remains Free/$0; optional Pro is a non-consumable purchase. The build validator checks configuration and warns about unresolved commercial policy classification; it does not establish publication, account eligibility or approval.

## OpenAI eligibility

OpenAI documents the local open-source flow without a developer client secret/API key. Users register connections during authorization. An MIT license in a private repository does not establish public open-source availability. [Quickstart](https://developers.openai.com/siwc/quickstart), [cookbook availability](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt).

If the product becomes paid, closed-source or remotely hosted, request access before offering that integration under the new model. The documentation does not explicitly classify free ChatGPT inside an app with paid API-provider features; review this uncertainty before public submission. The official form confirmed receipt of the request for this exact arrangement on 14 October 2026. Receipt is not approval. Source publication, live account access and commercial approval are separate evidence; none substitutes for another.
