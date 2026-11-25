# Mobile Windows Steam research (iOS and iPadOS)

Status: the Steam-first source overlay is implemented; full mobile engine build and device validation are pending. Neither iOS nor iPadOS is supported by GameBridge yet.

## Pinned upstream

- [Madeira source revision](https://github.com/willfaust/Madeira/commit/fbad430410b4075192166172447c859714726de9)
- [Desktop Steam experiment](https://github.com/willfaust/Madeira/blob/fbad430410b4075192166172447c859714726de9/app/Madeira/ContentView.swift): the developer action named Steam Testing calls prepareSteamLaunch and runs the Wine sequence.
- [Dock limitations](https://github.com/willfaust/Madeira/blob/fbad430410b4075192166172447c859714726de9/docs/MADEIRA_DOCK.md): headless client host, not the desktop interface. Not the target product.
- [Build record](https://github.com/willfaust/Madeira/blob/fbad430410b4075192166172447c859714726de9/docs/BUILDING.md) and [licensing](https://github.com/willfaust/Madeira/blob/fbad430410b4075192166172447c859714726de9/docs/LICENSING.md).

The pinned tree has separate Wine, FEX, DXMT and Dock gitlinks. Its build record identifies external toolchains, license-bound inputs and unverified clean-build steps. Upstream source availability, full build and current compatibility are not assumed. The experimental desktop route itself is not ready for normal login or release: review its CEF isolation, JIT and guest memory handling first. No Steam DLL, login files, pairing material or proprietary binaries are imported into this repo.

## Reproducible research checkout

On a developer machine:

```sh
bash scripts/prepare-mobile-engine.sh --prepare
```

The script uses an ignored isolated build directory, verifies the exact revision and expected research entrypoint and resolves recursive gitlinks. It neither builds nor installs anything in prepare mode. If source fetch fails, record the exact missing gitlink. After source, license and build-input review, a developer using macOS/Xcode/Homebrew can explicitly run:

```sh
bash scripts/prepare-mobile-engine.sh --build
```

This invokes upstream's build process (including its Homebrew dependencies). It is a research build of Madeira, not a GameBridge IPA, and has not been executed here. Follow the upstream build record for absent inputs. Do not distribute the output or substitute an unrelated prebuilt engine. Do not copy login credentials or tokens from another machine. Development signing and JIT availability must be assessed on each device; paid signing is not proof of JIT availability.

## Steam-first research host (third iteration)

The [source patch](../mobile/patches/0001-steam-first-research.patch) uses Madeira's existing experimental Big Picture session lifecycle (LibraryEntry.bigPictureEntry and launchLibraryEntry) but opens Valve's normal Windows Steam desktop. The home page has Open Steam rather than a game library, preserves the upstream JIT setup and full-screen guest renderer, and does not sign in through the headless Dock host. The research batch uses a separate Steam folder, does not seed it from Dock, does not disable Chromium sandboxing, and does not freeze Steam updates. This may expose additional guest compatibility failures; those failures must be resolved, not hidden.

```sh
bash scripts/prepare-mobile-engine.sh --steam-first-prepare
# On a reviewed macOS development environment, explicitly:
bash scripts/prepare-mobile-engine.sh --steam-first-build
```

The Steam-first checkout has its own directory suffix. The script validates the tracked working tree against a temporary Git index, applies both pinned overlays, and checks recursive submodule revisions. The research Xcode project now sets the separate bundle identifier `org.enostudio.gamebridge.research` for the app (with inherited extension suffixes), the display name GameBridge Research, and the separate `gamebridge-research://jit-network/` callback scheme. These are proposed development identifiers, not registered signing credentials; remaining upstream identity assumptions and entitlements must be checked on device. The upstream IPA filename still says Madeira. No ready-to-install IPA is provided.

## First-run Steam bootstrap (fourth iteration)

Pressing Open Steam in the research UI invokes a new method on the upstream SteamRuntimeInstaller actor when the isolated client executable is absent. It uses the existing pinned Valve CDN `steam_win32.zip` package (2,307,664 bytes), HTTPS host-restricted redirects, exact SHA-256 and the upstream strict ZIP parser. It extracts only `steam.exe`, checks its MZ header, preserves existing registry/prefix data, and publishes through a unique temporary file without overwriting an existing client. The same idle guest checks are performed before download and before installation. Existing installations are reused. Steam itself must complete the rest of the installation and update; this has not yet been tested on iPhone/iPad. A hash mismatch, absent package, missing executable or active session fails rather than silently fetching an untrusted replacement.

The separate client path remains `drive_c/Program Files/Steam Big Picture` for compatibility with the existing Wine desktop session. No Valve credential files, pinned Dock installation or third-party DLLs are copied. Do not use a personal account before security and stability gates pass. Full PE validation, disk-space checks, bounded streaming download, bootstrap architecture compatibility, security review and device validation remain outstanding.

CI checks the exact upstream patch application and downloads the pinned bootstrap archive for size, hash and executable-entry verification without executing it. This does not substitute for the full mobile build.

## Shared dependency preflight (fifth iteration)

The Windows PE reader, runtime family classifier and read-only dependency audit now live in GameBridgeCore. The mobile overlay compiles exact copies of those sources, checked with cmp during preparation and CI. Before opening Steam, the research host scans the isolated default Steam client game directories (up to 16 games and 256 EXE/DLL files per game). It records incomplete scans and unresolved import families, not a proof that every DLL is absent. Additional libraries, incremental scan coverage, dynamic loader events and game integrity verification are still pending.

The first-run screen has a persistent, initially off option to prepare Microsoft Visual C++ 2015–2022. When authorized, the existing upstream extractor downloads only absent architecture packages, uses pinned Microsoft hashes and validates the extracted files before publishing a fresh runtime folder. Valid existing runtimes are reused; conflicting or partial custom folders are preserved and reported. The upstream bridge applies the overlays at guest startup, not while Steam is running. This path is source integration only until a mobile build and device session pass. The old Visual C++ 2005–2013, DirectX, .NET, XNA, PhysX and OpenAL are recognized where imports expose them; automatic installation of those families on mobile is not implemented.

CI now checks the top-level FEX, Wine, DXMT and Dock gitlink commits are obtainable without building them. Nested dependencies, native toolchains and the full IPA build remain separate gates.

## Mobile integration sequence

1. Clean source build for arm64 iPhoneOS and physical iPhone/iPad; verify architecture, entitlements, source provenance and redistribution rights.
2. Exercise x86 and x64 test programs and a guest virtual desktop, then confirm real Steam desktop binaries start. Investigate CEF process, window/rendering, memory and network failures independently; no headless launcher or fake storefront counts.
3. Verify the Steam-first host source overlay and existing in-process guest lifecycle; validate first-run official bootstrap provisioning, the distinct bundle identity, and on-device security review. Keep sign-in and game operations in Valve's own interface.
4. Port the shared manifest and repair policy. Use sandbox-relative paths and idle guest boundaries; never overwrite DLLs in a live guest.
5. Test install/update/validation, Steam Guard, store/library, two game architectures, input, audio, saves, interruption and restart on both device classes. Do not declare support based on simulator compilation.

No App Store promise, no mandatory streaming, no paid runtime, no anti-cheat or DRM bypass.
