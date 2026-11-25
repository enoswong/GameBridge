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

The Steam-first checkout has its own directory suffix. The script validates the full tracked working tree against a temporary Git index, applies the pinned overlay, and checks recursive submodule revisions. The upstream build and code signing remain unverified. The output still uses Madeira's upstream IPA name and bundle identity; **do not install over an existing Madeira installation**. A distinct GameBridge application identity and reviewed entitlements are required before device distribution. No ready-to-install IPA is provided.

The research route currently requires an independently obtained, authorized Steam executable staged in the guest's existing isolated `drive_c/Program Files/Steam Big Picture` folder. There is no automatic Steam bootstrapper provisioning yet. Do not copy credentials or use a personal account before the CEF isolation and stability gates pass. The patched path may fail with the current Wine/CEF implementation.

## Mobile integration sequence

1. Clean source build for arm64 iPhoneOS and physical iPhone/iPad; verify architecture, entitlements, source provenance and redistribution rights.
2. Exercise x86 and x64 test programs and a guest virtual desktop, then confirm real Steam desktop binaries start. Investigate CEF process, window/rendering, memory and network failures independently; no headless launcher or fake storefront counts.
3. Verify the Steam-first host source overlay and existing in-process guest lifecycle; complete automatic official-client provisioning, distinct bundle identity and on-device security review. Keep sign-in and game operations in Valve's own interface.
4. Port the shared manifest and repair policy. Use sandbox-relative paths and idle guest boundaries; never overwrite DLLs in a live guest.
5. Test install/update/validation, Steam Guard, store/library, two game architectures, input, audio, saves, interruption and restart on both device classes. Do not declare support based on simulator compilation.

No App Store promise, no mandatory streaming, no paid runtime, no anti-cheat or DRM bypass.
