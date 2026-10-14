# Third-party notices and asset provenance

## OnDeviceMax / iOS Local LLM

Reference source: [Mesutcydev/ios-local-llm](https://github.com/Mesutcydev/ios-local-llm). Selected UI components were adapted under the original MIT license. The exact source commit, dirty-worktree hashes and file mapping are in `Docs/PROVENANCE.json` and `Docs/REFERENCE_BASELINE.json`. The original MIT copyright and permission notice is preserved in `LICENSE`.

No model weights, generated Core ML models, native local-model XCFrameworks, CoreAI/MLX/llama/Whisper frameworks, camera utilities or reference credentials are distributed with Repo Manager. The independent code and documentation use the repository's MIT terms; third-party material keeps its own license.

## Swift-Sodium 0.11.0

Source: [jedisct1/swift-sodium, 0.11.0](https://github.com/jedisct1/swift-sodium/releases/tag/0.11.0).

- Exact revision: `cfd195c76882aa9b997560ca7cb95d72fbf5db00`.
- License: ISC; preserved at `LICENSES/Swift-Sodium-0.11.0-ISC.txt`.
- The bundled `Clibsodium.xcframework` is an upstream binary, not generated in OnDeviceMax or copied from another app. The resolved checkout, binary slices, source/build script and file hashes are in `Docs/DEPENDENCY_PROVENANCE.json`.
- Purpose: GitHub sealed boxes and Argon2id portable-backup password derivation.

## Bundled libsodium

- Version reported by pinned headers: 1.0.22.
- Source revision recorded by upstream build script: `8cda270b3b18ca103c57085752cece1ebbf5abee`.
- Source: [jedisct1/libsodium](https://github.com/jedisct1/libsodium/tree/8cda270b3b18ca103c57085752cece1ebbf5abee) (no binary rebuild is asserted).
- License: ISC; preserved at `LICENSES/libsodium-1.0.22-ISC.txt`, retrieved from that source revision.

Upstream ISC notices permit redistribution with their copyright/permission notices. No GPL runtime or model license is introduced. Dependency downloads/build products remain outside Git.

## Brand assets

The repository-case logo was generated through OpenAI ImageGen for this user and selected in this conversation. Original generated raster sources, output identifiers, palette and prepared assets are recorded in `BrandKit/README.md` and design provenance. App icon, onboarding, launch mark and animation layers derive from that selected artwork. SF Symbols and system typography are used through Apple's platform APIs and are not redistributed as standalone font files.

Research examples (GitHub Mobile, Working Copy, Code App, Cline and Aider) informed feature choices. Their trademarks/screenshots/icons are not bundled as app artwork. Apple frameworks ship with the OS; no Apple system model weights or voices are copied into this repository.
