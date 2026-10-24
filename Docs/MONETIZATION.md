# Free core and one-time Pro

24 October 2026. Repo Manager is an MIT open-source app. ChatGPT sign-in and eligible plan usage are always free in Repo Manager. Apple Intelligence on supported devices and the GitHub workspace are also included. Optional Pro unlocks only API-key providers and custom compatible HTTPS endpoints.

The US base price is **$9.99 once**, a non-consumable StoreKit purchase, with no app subscription. The app displays StoreKit’s localized `Product.displayPrice`; the provider bills API usage separately. Neither API credits nor a ChatGPT subscription are included. ChatGPT eligibility and plan limits still apply.

## Source license and store purchase

The complete source remains MIT licensed, including the provider adapters and purchase implementation. Pro describes the optional feature unlock in the official App Store binary. It does not add a restriction to the MIT source license. People building a fork use their own signing, service registrations and credentials; [SETUP.md](../SETUP.md) explains the purchase configuration.

## Access enforcement

`ProviderAccessPolicy` checks ChatGPT authentication before the provider preset. A ChatGPT profile remains free even when its preset is OpenAI, Pro is unowned, or a purchase is refunded. Apple profiles are also exempt. API-key and custom profiles pass through `ProviderAccessGate` before invoking the provider. Verified StoreKit entitlements grant access; refunds and revocations remove it.

The paywall uses the app’s semantic graphite, ivory and emerald palette, repository-case mark, solid cards with fine borders and accessible typography. Benefits precede an explicit “ChatGPT stays free” card. The whole sheet scrolls at short heights and large text sizes. Purchase, restore, pending approval, cancellation, unavailable price and retry states are handled.

## Release candidate

Build 24 deliberately enables ChatGPT and optional Pro in Debug, TestFlight and Release. Debug fixtures are compiled out of production. `REPO_MANAGER_CHATGPT_MONETIZATION_CLEARED` remains NO: this records that no commercial-access approval has been verified; it is not used to charge for or gate ChatGPT. The build validator warns about the external policy classification without treating an unclassified arrangement as a confirmed denial.

OpenAI’s local/open-source documentation directs paid or remotely hosted apps to request access. It does not explicitly classify this app’s free-ChatGPT/optional-other-provider model. The access request was received on 14 October; receipt does not establish approval. Review this uncertainty before public submission. Sources: [Sign in with ChatGPT](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt#usage-policy-and-terms), [Open-source token sharing](https://developers.openai.com/siwc/token-sharing-open-source#introduction).

## Store setup and acceptance

Product: `com.mesutcydev.repomanager.pro.apiProviders`. Regional availability matches the parent app’s 174 enabled territories; France remains excluded. New territories are not enabled automatically. Family Sharing remains off. Display text is localized in the app’s seven languages.

The `RepoManagerStoreKitTests` scheme exercises local StoreKit transactions. Debug UI fixtures preview the flow without payment. Neither establishes actual Apple Sandbox purchase acceptance. The owner elected to perform the physical-device Sandbox purchase, cancellation, fresh-install restore and refund/revocation checks before submission. Local StoreKit transaction tests and native dark/light/large-text RTL renders passed. The interactive Simulator runner failed to launch the app, so no passing interactive run is claimed. The exact archived source is public at [v1.0-build.24](https://github.com/Mesutcydev/RepoManager/tree/v1.0-build.24); internal account and QA evidence is excluded from the public repository.
