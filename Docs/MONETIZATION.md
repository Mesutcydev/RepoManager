# Free core and one-time Pro

14 October 2026. The owner selected **$9.99 once** as the base US price for Repo Manager Pro. ChatGPT connection, Apple Intelligence and the GitHub workspace remain included. StoreKit purchase/restore code and API-provider access checks are prepared, with Pro rollout disabled in Debug, TestFlight and Release. The existing TestFlight build 9 offers no purchase or paywall. A draft non-consumable is created in App Store Connect, with a saved $9.99 US base price, Apple's comparable prices and English display text. Its regional availability, actual sandbox verification and review remain pending; it is not offered for sale.

## Proposed access

| Included in the free core | Proposed one-time Pro unlock |
| --- | --- |
| Continue with ChatGPT using the user's eligible account and authorized plan allowance | API-key provider profiles, including the OpenAI API and other supported hosted APIs |
| Apple Intelligence when available on the user's device | Custom compatible HTTPS model endpoints |
| Repository browsing, chat and native review/approval of GitHub changes | Using those API profiles in chat, comparison and the authorized local agent API |

ChatGPT connection is included; this does not provide a ChatGPT subscription, guarantee eligibility or remove OpenAI usage limits. A user's ChatGPT subscription is separate from Repo Manager Pro. Pro unlocks app functionality, with no API credits or model usage bundled. API usage is billed by the selected provider under the user's own account.

## OpenAI access decision

The official local/open-source integration documentation directs **paid or remotely hosted apps** to request access before offering the integration. It does not explicitly exempt an app that keeps ChatGPT free while charging only for API-provider features. This freemium arrangement therefore needs confirmation from OpenAI before a public paid version retains ChatGPT plan usage. Publishing MIT source is not evidence of commercial access approval.

[Official usage policy](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt#usage-policy-and-terms), [local integration overview](https://developers.openai.com/siwc/token-sharing-open-source).

The official access request for this exact model was submitted on 14 October 2026 and the form confirmed receipt. This is not an approval. Complete source is public at [Mesutcydev/RepoManager](https://github.com/Mesutcydev/RepoManager). Public Release ChatGPT and paid Pro remain disabled pending the applicable access decision and completed App Store setup/testing.

## Prepared implementation

- One non-consumable StoreKit product: `com.mesutcydev.repomanager.pro.apiProviders`, base US price **$9.99**. The purchase screen uses StoreKit's localized `displayPrice`. The draft App Store product and its comparable localized prices are saved; regional availability and actual sandbox checkout still need verification.
- Purchase, restore and transaction-update handling based on verified StoreKit transactions. Revoked/refunded transactions remove the Pro entitlement.
- Classify ChatGPT by its authentication method before checking the OpenAI provider preset. ChatGPT and Apple profiles remain included; API-key/custom profiles require Pro.
- Enforce API access at request/catalog routing as well as provider configuration and UI. Imported/existing profile metadata remains available without silently deleting credentials or changing the selected destination.
- Explain the one-time unlock, the exact features and separate upstream API billing before purchase. Preserve dismissible purchase UI, Restore Purchases, loading/error/cancellation states and accessibility.
- Verify the included ChatGPT/Apple paths, every API preset/custom endpoint, restored purchases, refunds/revocation and direct/local-agent request paths with synthetic or StoreKit test transactions. A local fixture is not a production purchase.

`REPO_MANAGER_PRO_API_PROVIDERS_ENABLED=NO` keeps provider access unchanged in ordinary builds. Debug-only `--ui-fixtures --pro-fixtures` previews the purchase screens without taking payment. Public paid ChatGPT enablement also requires `REPO_MANAGER_CHATGPT_MONETIZATION_CLEARED=YES`, which must reflect the actual OpenAI access decision; a received form or an owner preference does not set it.

Before offering Pro, finish the draft product's regional availability and review metadata, verify the actual sandbox purchase/restore/refund behavior, confirm applicable commercial access and then deliberately enable rollout. TestFlight build 9 remains the previously delivered payment-free beta.

The dedicated `RepoManagerStoreKitTests` scheme uses the local `Tests/NativeSecurity/RepoManagerPro.storekit` configuration and US test locale. It verifies StoreKit purchase, a fresh owner restore, automatic refund handling, the displayed $9.99 price and API access, while ChatGPT/Apple remain included. These are local test transactions, not App Store sandbox or production receipts. The ordinary scheme skips this suite so it does not require a StoreKit test environment.

For iOS digital feature unlocks, the standard App Store route is in-app purchase; storefront-specific alternatives have separate requirements. [Apple's payment rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase).

## Open-source license

The complete app remains MIT-licensed, with upstream notices retained. MIT permits commercial distribution and also permits users to modify, redistribute and sell their own forks. A client-only paywall can be removed in a fork; payment enforcement does not depend on concealing source or embedding developer secrets. The official build's convenience, maintenance and support provide value.

[MIT license](https://opensource.org/license/mit).
