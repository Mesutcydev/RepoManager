# Free open-source release preparation

14 October 2026. Complete MIT source is public. An optional **$9.99 one-time Pro** unlock for API-provider support is prepared, with rollout disabled. ChatGPT connection and Apple Intelligence remain included. The OpenAI form confirmed receipt of the access request; its decision and completed App Store setup/testing are pending. The non-consumable draft and $9.99 US price are saved. See [MONETIZATION.md](MONETIZATION.md).

## Prepared locally

- Preserve the existing MIT license, upstream copyright notices, Swift-Sodium/libsodium licenses and bundled third-party notices.
- Include the complete native app, Share extension, core/UI packages, source assets, package pins, build configuration, source validators and tests.
- Support official **Continue with ChatGPT**, independently of API-key providers and GitHub sign-in.
- Explain that the app is free, API-key providers bill their own usage, and eligible ChatGPT requests use the authorized user's plan.
- Generate the reviewable public-source ZIP with `python3 scripts/prepare_open_source.py`. It contains build sources, public documentation, a public README and SHA-256 manifest. It excludes Git history, caches, signing files, personal QA logs/screenshots, TestFlight receipts and App Store evidence.

## Published source

Complete source is published at [Mesutcydev/RepoManager](https://github.com/Mesutcydev/RepoManager), with a fresh history containing only the reviewed public snapshot. The original development workspace's private QA files, account evidence and existing Git state were preserved and are not part of that history. Source publication does not change App Store pricing or submit an App Store release.

The source ZIP's hashes and license/asset notices were checked, and the extracted source built for iOS Simulator with signing disabled. Anonymous download verifies the published source against that clean snapshot. Forks should configure their own signing identities and GitHub App.

`REPO_MANAGER_OPEN_SOURCE_URL` now points to the actual public repository. Public Release ChatGPT enablement remains a separate decision: a payment-free local open-source release can use its documented route, while the proposed monetized version needs the applicable OpenAI access confirmation before offering the integration. Regenerate and run the release prebuild check when enabling it. This URL check is a declaration guard; verify anonymous access separately.

The user separately requested an enabled TestFlight beta for personal on-device testing on 14 October. The dedicated `TestFlight` build configuration enables ChatGPT with Release optimization while ordinary public `Release` stays disabled. This beta does not establish public-source publication or approved partner access. Live account eligibility remains a beta check.

Complete the live checks in [the integration guide](CHATGPT_SIGN_IN.md), then review store privacy metadata for verified account identity and optional plan usage. The app download and existing payment-free beta remain Free/$0. The prepared optional Pro product must be configured, reviewed and tested before activation; source publication does not create an in-app purchase or change App Store pricing. Existing TestFlight/App Store publication gates still apply.

## OpenAI eligibility

OpenAI documents the local open-source flow without a developer client secret/API key. Users register connections during authorization. An MIT license in a private repository does not establish public open-source availability. [Quickstart](https://developers.openai.com/siwc/quickstart), [cookbook availability](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt).

If the product becomes paid, closed-source or remotely hosted, request access before offering that integration under the new model. The documentation does not explicitly exempt free ChatGPT inside an app with paid API-provider features. The official form confirmed receipt of the request for this exact arrangement on 14 October 2026. Receipt is not approval. Source publication, live account access and commercial approval are separate evidence; none substitutes for another.
