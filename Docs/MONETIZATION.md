# Free core and one-time Pro

14 October 2026. The owner selected a one-time Pro unlock, with ChatGPT connection remaining in the free core and API-provider support as the proposed paid feature. This is a product plan; no Pro product, purchase or paywall is offered in the current build.

## Proposed access

| Included in the free core | Proposed one-time Pro unlock |
| --- | --- |
| Continue with ChatGPT using the user's eligible account and authorized plan allowance | API-key provider profiles, including the OpenAI API and other supported hosted APIs |
| Apple Intelligence when available on the user's device | Custom compatible HTTPS model endpoints |
| Repository browsing, chat and native review/approval of GitHub changes | Using those API profiles in chat, comparison and the authorized local agent API |

ChatGPT connection is included; this does not provide a ChatGPT subscription, guarantee eligibility or remove OpenAI usage limits. A user's ChatGPT subscription is separate from Repo Manager Pro. Pro would unlock app functionality, with no API credits or model usage bundled. API usage is billed by the selected provider under the user's own account.

## OpenAI access decision

The official local/open-source integration documentation directs **paid or remotely hosted apps** to request access before offering the integration. It does not explicitly exempt an app that keeps ChatGPT free while charging only for API-provider features. This freemium arrangement therefore needs confirmation from OpenAI before a public paid version retains ChatGPT plan usage. Publishing MIT source is not evidence of commercial access approval.

[Official usage policy](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt#usage-policy-and-terms), [local integration overview](https://developers.openai.com/siwc/token-sharing-open-source).

The existing personal TestFlight build and source snapshot contain no purchase flow. Public Release ChatGPT enablement remains a separate, explicit configuration decision after source publication and the applicable OpenAI access decision. A payment-free current build can be published as source while this future monetization decision is pending.

## Planned implementation

- One non-consumable StoreKit product; final identifier and price are selected before product creation. Use StoreKit's localized product price rather than a hard-coded currency.
- Purchase, restore and transaction-update handling based on verified StoreKit transactions. Revoked/refunded transactions remove the Pro entitlement.
- Classify ChatGPT by its authentication method before checking the OpenAI provider preset. ChatGPT and Apple profiles remain included; API-key/custom profiles require Pro.
- Enforce API access at request/catalog routing as well as provider configuration and UI. Imported/existing profile metadata remains available without silently deleting credentials or changing the selected destination.
- Explain the one-time unlock, the exact features and separate upstream API billing before purchase. Preserve dismissible purchase UI, Restore Purchases, loading/error/cancellation states and accessibility.
- Verify the included ChatGPT/Apple paths, every API preset/custom endpoint, restored purchases, refunds/revocation and direct/local-agent request paths with synthetic or StoreKit test transactions. A local fixture is not a production purchase.

For iOS digital feature unlocks, the standard App Store route is in-app purchase; storefront-specific alternatives have separate requirements. [Apple's payment rules](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase).

## Open-source license

The complete app remains MIT-licensed, with upstream notices retained. MIT permits commercial distribution and also permits users to modify, redistribute and sell their own forks. A client-only paywall can be removed in a fork; payment enforcement does not depend on concealing source or embedding developer secrets. The official build's convenience, maintenance and support provide value.

[MIT license](https://opensource.org/license/mit).
