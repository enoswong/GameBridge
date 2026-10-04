# GameBridge

[繁體中文](https://github.com/enoswong/GameBridge#readme) · [简体中文](README.zh-CN.md) · **English** · [Command reference / 指令教學](../COMMANDS.md)

GameBridge is a macOS Windows gaming and environment manager based on [Whisky](https://github.com/Whisky-App/Whisky), designed for Apple Silicon Macs. It brings together Windows Steam setup, isolated containers and targeted compatibility fixes.

> **Availability — October 4, 2026:** the public release currently contains source code. A complete application download has not been published. The application instructions below apply to a test build containing the bootstrap resources. Building the source alone does not supply the complete runtime.
>
> The planned public test build will **not be Developer ID signed or Apple-notarized**. Runtime provenance, third-party licensing and distribution validation are still in progress. Check the actual assets and notes on [Releases](https://github.com/enoswong/GameBridge/releases).

## Features

- One-click preparation of a Windows environment, Windows Steam and common prerequisites.
- Independent containers with their own programs, registry and installed components.
- Targeted DXMT/DirectX 11, DLL loading, transparent-window and mouse-input compatibility fixes.
- Preparation of applicable bundled fixes when launching supported existing environments.
- Setup checkpoints for retrying interrupted installation.
- Environment recovery, reversible removal, file-location controls and execution logs.

Fixes apply to supported engines and specific game behavior; they do not guarantee compatibility with every game. Clean-data-directory setup and selected games have been validated on the development Mac. A second physical Mac has not yet been validated.

## Requirements

- **Apple Silicon Mac:** an Apple M-series chip. Intel Macs are not the target of this workflow.
- **macOS 15 or later:** the current application deployment target; individual OS/game combinations still require testing.
- **Rosetta:** required by the current runtime. GameBridge does not install it automatically. Follow macOS prompts or [Apple's Rosetta instructions](https://support.apple.com/102527).
- **Local APFS storage:** allow space for the runtime, Windows components, Steam, games and updates.
- **Internet access and your own Steam account:** Steam handles sign-in, Steam Guard, purchases and game downloads.

You do not need a full Windows installation. An existing macOS Steam installation does not replace Windows Steam inside GameBridge.

## Download and install

1. Open [Releases](https://github.com/enoswong/GameBridge/releases) and read the version notes.
2. Download an asset explicitly described as an application package, when available.
3. Extract it and move `GameBridge.app` into **Applications**.
4. Launch GameBridge from Applications and respond to relevant macOS prompts.

`GameBridge-public-source.zip`, `Source code (zip)` and `Source code (tar.gz)` are source archives, not complete installable application packages. If the release has no application asset, the binary is not available yet.

If the release provides a SHA-256 checksum, verify your download with the [command reference](../COMMANDS.md).

### First launch of an unnotarized build

If macOS cannot verify the developer or check the app, first confirm that the file came from this project's Release and matches its published checksum:

1. Try opening GameBridge once.
2. Open **System Settings → Privacy & Security**.
3. Find the GameBridge notice and choose **Open Anyway**, if available.
4. Confirm **Open** in the follow-up dialog.

This creates an exception for the app; there is no need to disable system-wide security checks. A damaged-file or malware warning needs investigation, not treatment as an ordinary notarization warning. See [Apple's instructions](https://support.apple.com/102445).

## First-time setup

The current interface uses Traditional Chinese labels. This guide includes those labels so you can find the controls; translating this README does not change the application's UI language.

In **GameBridge · Windows Steam**:

1. Under First use (`首次使用`), choose **Read Microsoft component terms** (`閱讀 Microsoft 元件條款`).
2. Read the terms and, if you accept them, check `我已閱讀並接受 Microsoft 元件授權條款`.
3. Choose **Prepare Windows Steam** (`一鍵準備 Windows Steam`).
4. Wait for setup and watch the execution log. Keep the connection available and do not move container files during installation.
5. When Windows Steam opens, complete its update, sign-in and account verification.

Setup prepares the verified runtime and environment, Visual C++ x64/x86 components, DirectX June 2010 components, Windows Steam and applicable compatibility fixes. Microsoft and Steam installers are downloaded from official sources and checked against pinned hashes. Account steps, purchases and any required publisher confirmation remain yours to complete. Games may need additional prerequisites.

If setup is interrupted, check **Execution log** (`執行記錄`), resolve network or storage problems and retry preparation. Completed stages are checkpointed. Exit Windows Steam first if it is holding the environment open.

If First use is absent, the build may lack bundled bootstrap resources. Repeatedly creating empty environments will not install a missing runtime.

## Install and play Windows games

1. Select the environment that completed setup in `Windows 環境`.
2. Choose **Open Windows Steam** (`開啟 Windows Steam`).
3. Sign in and open your Steam library in that Windows Steam window.
4. Install a game using the environment's default library location initially.
5. Wait for downloads and game prerequisites, then select Play.

Use **Windows Steam launched through GameBridge** to install Windows editions. Games downloaded by macOS Steam are not automatically converted. For titles offering both editions, verify that you are installing and launching through Windows Steam.

Some automatic fixes currently require the game to be on the container's `C:` drive. External/custom Steam libraries are not covered by the complete provisioning workflow.

Verify launch, rendering, keyboard/mouse input, saving and exit separately. A visible game window alone does not establish full compatibility.

## Everyday launch and exit

Open GameBridge, select the original environment, choose `開啟 Windows Steam`, then launch from Steam. You do not need to reinstall components each time.

Save and exit the game, then choose **Steam → Exit** in Windows Steam. Closing its window may leave Steam running. Complete this exit sequence before updating the application, removing an environment or recovering its state.

Use the normal GameBridge → Windows Steam → game path so applicable compatibility settings are applied.

## Containers and file locations

Each container (Wine prefix) has separate installed DLLs, programs and registry state. Installing a component in container A does not install it in B.

| Control | Purpose |
| --- | --- |
| `建立 Windows 環境` | Create an environment using the selected engine and name; this alone is not full one-click setup |
| `初始化` | Initialize Windows files in a newly created environment |
| `安裝 Windows Steam…` | Select official `SteamSetup.exe` for manual installation into the selected environment, not the Mac Steam.app |
| `辨識已安裝的 Steam` | Register Steam already installed in that environment |
| `開啟 Windows Steam` | Launch the selected environment's Steam |
| `在 Finder 顯示` | Locate that container's folder |
| `恢復環境狀態` | Recover state after interruption once the environment is idle; this does not restore game saves |
| `移除環境…` | Remove the environment from the active list while retaining its files |
| `重新整理` | Refresh environment and engine state |

The engine picker `建立環境的引擎` applies to new environments. `目前環境引擎` shows the actual engine bound to the selected existing environment; changing the creation picker does not migrate it.

### Locate games

Use `在 Finder 顯示` and open `drive_c`, the virtual Windows `C:` drive. Steam's default game directory is usually `drive_c/Program Files (x86)/Steam/steamapps/common`; the actual path depends on Steam settings. Steam's game-management controls can also browse local files.

Windows `C:` is not the macOS Applications folder. When selecting a Steam installer, return to the folder where you downloaded `SteamSetup.exe`; when browsing an installed game, start from the container's `drive_c`.

### Remove and restore

Exit games and Windows Steam, select the environment, then choose `移除環境…` and confirm. To restore it, expand `已移除的環境（可恢復）` and choose `恢復` beside it.

**Removal retains games and saves and does not reclaim their disk space.** This workflow does not provide permanent cleanup. Do not delete unfamiliar container files to free space.

## Updates and backups

1. Save your game and check Steam Cloud synchronization if used.
2. Exit the game, Windows Steam and GameBridge.
3. For a private local backup, locate the container first and copy the entire folder while it is idle. This is a data backup, not a supported one-click cross-device import.
4. Download and verify the new application package, read its notes and replace GameBridge.app in Applications.
5. Reopen the existing environment through `開啟 Windows Steam`.

Normal launch checks/prepares applicable bundled fixes. It does not promise migration of every engine, custom DLL or external library.

Backups may contain your Steam session and personal data. Keep them private. Public project source and distribution packages do not contain the developer's Steam account or personal containers.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Only source files, no app | You downloaded a source asset. Check whether an application asset has been published |
| No one-click setup or verified engine | Verify the build includes bootstrap resources; source compilation alone does not provide them |
| Preparation button disabled | Read/accept the component terms and wait for any active preparation operation |
| Download or checksum failure | Check network, free space and logs. Report persistent failures; do not bypass verification |
| New environment lacks DLLs | Components are per-container. Use an environment that completed prerequisite setup |
| Missing Visual C++ error | Verify the game and installed prerequisites are in the same environment; record the exact error and engine version |
| Steam installed but unavailable | Check the selected container and use `辨識已安裝的 Steam` if registration is missing |
| No Steam window / steamwebhelper.exe error | Exit Steam, recover state if needed after it stops, then retry. Report persistent failures with logs |
| Missing container | Refresh and check `已移除的環境（可恢復）` |
| Cannot remove a container | Exit games and Steam; recover interrupted state if required. Running environments cannot be removed |
| Scene renders but clicks/transparency fail | Check the current build, correct environment, normal launch path and installation inside C:. Report remaining problems before modifying game files |
| Want to copy DLLs from another environment | Keep the original environment; use supported setup instead of overwriting system DLLs with a different engine's files |

DirectX June 2010 installation and DXMT graphics translation are different steps. Reinstalling DirectX is not a universal graphics fix. Anti-cheat, DRM, video playback and other dependencies require game-specific testing.

## Commands

The GUI is sufficient for ordinary use. See the [multilingual command reference](../COMMANDS.md) for macOS Terminal commands covering checksums, CLI help, setup, environment inspection, launch, recovery and developer builds. Windows CMD is not required for normal setup.

## Report an issue

Use [GitHub Issues](https://github.com/enoswong/GameBridge/issues). Include the app version/package or commit, Mac chip, macOS version, selected environment and actual engine version, failing stage, reproduction steps and a redacted error/log excerpt.

Do not upload containers, Steam login files, Steam Guard codes, tokens or entire personal directories. Redact account identifiers and private paths.

## Developer build

Use an Apple Silicon Mac with compatible Xcode and Command Line Tools. From the repository root:

```sh
swift test --package-path WhiskyKit
bash scripts/build-local.sh
```

The output is `build/local/Build/Products/Debug/GameBridge.app`. The build script uses fixed package resolution; see the [command reference](../COMMANDS.md) to resolve dependencies into its expected directory first.

This produces an unsigned Debug build, not a complete public distribution. Bootstrap resources require separate preparation. Read [release status](../release/STATUS.md) and the [runtime audit](../release/RUNTIME-AUDIT-2026-10-04.md).

## Sources and license

Based on Whisky commit `fd5480a76b3ebfe3419a1ab86ca3695f5cc328f8`, retaining its [GPL-3.0-or-later license](../../LICENSE), notices and Git history. New GameBridge application/compatibility sources also use GPL-3.0-or-later; third-party components retain their respective licenses.

Thanks to Whisky, Wine, DXMT and related open-source projects. GameBridge is not an official release of Whisky, Wine, DXMT, Steam, Microsoft or Apple.
