# Mobile Windows Steam research (iOS and iPadOS)

Status: source integration preparation only. Neither iOS nor iPadOS is supported by GameBridge yet.

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

## Mobile integration sequence

1. Clean source build for arm64 iPhoneOS and physical iPhone/iPad; verify architecture, entitlements, source provenance and redistribution rights.
2. Exercise x86 and x64 test programs and a guest virtual desktop, then confirm real Steam desktop binaries start. Investigate CEF process, window/rendering, memory and network failures independently; no headless launcher or fake storefront counts.
3. Build a new Steam-first host UI using the upstream in-process desktop and input primitives only after the guest lifecycle is verified. Keep sign-in and game operations in Valve's own interface.
4. Port the shared manifest and repair policy. Use sandbox-relative paths and idle guest boundaries; never overwrite DLLs in a live guest.
5. Test install/update/validation, Steam Guard, store/library, two game architectures, input, audio, saves, interruption and restart on both device classes. Do not declare support based on simulator compilation.

No App Store promise, no mandatory streaming, no paid runtime, no anti-cheat or DRM bypass.
