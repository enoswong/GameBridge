# GameBridge Universal development gates

This branch builds on the guided Steam preview without merging it into main.
The product is a transparent Windows Steam environment, not a replacement Steam library.

## Implemented in the first iteration
- macOS Steam-first main screen; game-specific controls remain diagnostic tools.
- Default-library dependency audit before Steam startup. Optional persistent repair authorization.
- Existing lease and idle checks remain required for installing components.
- Portable GameBridgeCore SwiftPM target contains the Steam manifest classification policy.
- Do not change the internalOnly runtime release gate.

## Next engineering gates
1. Verify all macOS builds, strict lint and regression tests. Real Mac: existing prefix, Steam login, download, update, launch, exit, and missing dependency case.
2. Incremental audit cache keyed by engine version, game build and file metadata; process/manifest event collection while Steam runs. Do not modify live DLLs or forcibly terminate Steam. Queue repairs for verified idle periods; validate safe retry and rollback.
3. Split additional pure models and state machines from WhiskyKit. Build only the portable target for iOS; existing WhiskyKit still uses macOS APIs.
4. Mobile local engine proof of concept: verify license/provenance, permitted execution and JIT availability on physical iPhone and iPad, x86/x64 program execution, Metal graphics and input.
5. Full Windows Steam gate: real steam.exe and steamwebhelper.exe, login, Steam Guard, store, library, download, update, game launch and official verification. Headless hosts or custom launchers do not satisfy this gate.
6. On-device lifecycle, memory/thermal handling, touch and controllers. No claim of mobile support until physical device acceptance.
7. Public distribution only after exact corresponding source, licenses, catalog signing and appropriate platform signing are resolved. See docs/release/STATUS.md.

No cloud service, paid runtime, automatic upload of credentials, or bypass of OS security is required by this plan. A streaming fallback, if later developed, must be explicitly labelled and opt-in.
