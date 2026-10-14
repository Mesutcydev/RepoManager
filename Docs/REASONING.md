# Adaptive reasoning

Research checked 11 October 2026. `ReasoningPolicy`, `ProviderRouting`, provider wire decoders and the Apple adapter are the implementation source of truth. Catalog metadata can change; refresh is explicit.

## Policy

The app offers Automatic, Off and the selected model's supported effort levels. Automatic uses prompt/task cues and voice latency to choose a bounded supported level; there is no billed classifier request. It respects 8,192 input and 4,096 output app budgets and lower known model limits. Automatic does not select maximum/xhigh or increase spending limits. An unsupported explicit level is reduced to a supported value with a visible explanation, or request construction fails for an incompatible protocol.

Three distinct behaviors are named honestly: native effort/adaptive control, provider-default reasoning, and answer-style guidance where no native reasoning contract is known. The app shows only supplied reasoning summaries/text. It cannot expose private internal thoughts and does not fabricate them.

## Provider contracts

| Family | Implementation |
| --- | --- |
| OpenAI | Responses/Chat Completions effort only for recognized models; model-specific supported levels. Preserve encrypted Responses continuation. GPT-6 Astra/6.1 Sol tools require Responses rather than unsupported Chat Completions tool use. |
| Anthropic | Adaptive thinking and documented effort for supported newer families; bounded legacy thinking budget where appropriate. Replay signed thinking blocks only to the same destination. |
| Gemini | Supported thinking level/budget controls; preserve thought signatures for tool continuation. |
| DeepSeek | Documented thinking/reasoner controls and signed-destination reasoning-content replay; no leaking across profiles/endpoints. |
| xAI | Model-specific effort or provider-default reasoning; avoid an invented effort flag on unsupported Grok variants. |
| Mistral | Preserve supplied thinking/text content arrays and native continuation; request native contract only for supported models. |
| OpenRouter | Prefer advertised supported efforts/default/mandatory/max-token reasoning metadata. Unknown models retain gateway defaults. Reassemble and replay `reasoning_details` without modifying opaque signatures. Catalog dollar-per-token prices are converted to per-million metadata. |
| OpenCode Go / Zen | Select Responses, Anthropic Messages, Gemini or compatible Chat Completions per documented model family and optional verified override. Truthful RepoManager User-Agent/session ID; no claim to be the OpenCode client. Unknown reasoning contracts preserve defaults. |
| Apple | OS 27 reasoning only when system capability permits; supported light/moderate/deep context options for system/PCC. Actual token usage and PCC context limits; PCC has no system `tokenCount` method, so preflight estimation is labelled. |
| Other/custom | Explicit verified capability metadata or answer-style guidance; no guessing hidden thinking support. |

Streaming normalizes text, tool calls, reasoning, input/output/reasoning usage, finish reason and safe errors. Split Unicode and final usage trailers are tested. Tool loops keep every actual protocol round for correct signed continuation. Continuation state requires exact profile ID, endpoint and model; copied/forked conversation state cannot be replayed to another destination.

## Sources

- [OpenAI reasoning](https://developers.openai.com/api/docs/guides/reasoning)
- [Anthropic adaptive thinking](https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking) and [effort](https://platform.claude.com/docs/en/build-with-claude/effort)
- [Gemini thinking](https://ai.google.dev/gemini-api/docs/generate-content/thinking)
- [DeepSeek thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/)
- [xAI reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning)
- [Mistral reasoning](https://docs.mistral.ai/studio/conversations/reasoning)
- [OpenRouter reasoning tokens](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens) and [model metadata](https://openrouter.ai/docs/guides/overview/models)
- [OpenCode Go](https://docs.opencode.ai/docs/go/) and [Zen](https://docs.opencode.ai/docs/zen/)
- [Apple Foundation Models](https://developer.apple.com/foundation-models-framework/) and [Private Cloud Compute model](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel)

OpenCode contributor/free/trial policy exceptions receive an additional native privacy disclosure. Consent is enforced before provider requests across chat, comparisons and agent routes. This disclosure does not assert every free model has the same policy.
