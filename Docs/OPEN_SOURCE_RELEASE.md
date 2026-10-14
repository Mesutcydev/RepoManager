# Free open-source release preparation

14 October 2026. The user chose MIT source publication and subsequently selected a future one-time Pro unlock for API-provider support, with ChatGPT connection remaining included. The current app has no purchase or paywall. The proposed paid model is documented in [MONETIZATION.md](MONETIZATION.md); its OpenAI access decision is pending.

## Prepared locally

- Preserve the existing MIT license, upstream copyright notices, Swift-Sodium/libsodium licenses and bundled third-party notices.
- Include the complete native app, Share extension, core/UI packages, source assets, package pins, build configuration, source validators and tests.
- Support official **Continue with ChatGPT**, independently of API-key providers and GitHub sign-in.
- Explain that the app is free, API-key providers bill their own usage, and eligible ChatGPT requests use the authorized user's plan.
- Generate the reviewable public-source ZIP with `python3 scripts/prepare_open_source.py`. It contains build sources, public documentation, a public README and SHA-256 manifest. It excludes Git history, caches, signing files, personal QA logs/screenshots, TestFlight receipts and App Store evidence.

## Before publishing

The workspace has no Git remote configured. This preparation does not create/make a repository public, upload source, or change the App Store price.

Choose the public repository destination, review the ZIP and license/asset provenance, and publish the complete source under MIT. Verify that an anonymous visitor can download and build it. Forks should configure their own signing identities and GitHub App.

Set the actual repository URL in `REPO_MANAGER_OPEN_SOURCE_URL` after publication. Public Release ChatGPT enablement is a separate decision: a payment-free local open-source release can use its documented route, while the proposed monetized version needs the applicable OpenAI access confirmation before offering the integration. Regenerate and run the release prebuild check when enabling it. This URL check is a declaration guard; verify anonymous access separately.

The user separately requested an enabled TestFlight beta for personal on-device testing on 14 October. The dedicated `TestFlight` build configuration enables ChatGPT with Release optimization while ordinary public `Release` stays disabled. This beta does not establish public-source publication or approved partner access. Live account eligibility remains a beta check.

Complete the live checks in [the integration guide](CHATGPT_SIGN_IN.md), then review store privacy metadata for verified account identity and optional plan usage. The current source/payment-free beta remains Free/$0. A future one-time Pro product must be explicitly configured, reviewed and tested; source publication does not create an in-app purchase or change App Store pricing. Existing TestFlight/App Store publication gates still apply.

## OpenAI eligibility

OpenAI documents the local open-source flow without a developer client secret/API key. Users register connections during authorization. An MIT license in a private repository does not establish public open-source availability. [Quickstart](https://developers.openai.com/siwc/quickstart), [cookbook availability](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt).

If the product becomes paid, closed-source or remotely hosted, request access before offering that integration under the new model. The documentation does not explicitly exempt free ChatGPT inside an app with paid API-provider features. A request for this exact arrangement is being prepared. Source publication, live account access and commercial approval are separate evidence; none substitutes for another.
