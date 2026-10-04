# 指令教學 / 命令指南 / Command reference

[繁體中文](https://github.com/enoswong/GameBridge#readme) · [简体中文](i18n/README.zh-CN.md) · [English](i18n/README.en.md)

## 1. 在哪裏輸入？ / 在哪里输入？ / Where to run commands

**繁體：**以下所有 `sh` 指令均在 macOS「終端機」執行，不是在 Windows CMD、PowerShell 或 Steam 啟動選項。一般使用可完全透過圖形介面完成，毋須輸入指令。公開應用程式包尚未上架；CLI 範例需要已有包含相應工具的測試包。文件翻譯不代表 app 介面已翻譯。

**简体：**以下所有 `sh` 命令均在 macOS“终端”执行，不是在 Windows CMD、PowerShell 或 Steam 启动选项。普通使用可以完全通过图形界面完成，无需输入命令。公开应用包尚未上架；CLI 示例需要已取得包含相应工具的测试包。文档翻译不代表应用界面已翻译。

**English:** Run all `sh` examples in **macOS Terminal**, not Windows CMD, PowerShell or Steam launch options. The GUI is sufficient for everyday use. A public application package is not yet available; CLI examples require an existing test build with the corresponding tools. Documentation translations do not change the app's UI language.

## 2. 開啟 app、核對下載 / 打开应用、检查下载 / Open app and verify download

```sh
open "/Applications/GameBridge.app"
```

SHA-256：輸入下列指令並加一個空格，把下載的 ZIP 拖入終端機，再按 Return；與該 Release 公布的值比較。输入命令加空格，拖入 ZIP 后回车，并与 Release 的值比较。Type the command followed by a space, drag the downloaded ZIP into Terminal, press Return and compare with the release checksum.

```sh
shasum -a 256
```

不要單獨執行沒有檔案參數的這一行，否則會等待標準輸入。不要单独运行没有文件参数的这一行，否则会等待标准输入。Do not execute the line without a file argument; it would wait for standard input.

未公證版本：按 README 的「私隱與保安」流程開啟，毋須執行關閉 Gatekeeper 的指令。未公证版本：按照 README 的系统设置流程打开，无需关闭 Gatekeeper。For unnotarized builds, follow the README's per-app Privacy & Security procedure; no system-wide Gatekeeper override is required.

## 3. 設定 CLI 路徑 / 设置 CLI 路径 / Set the CLI path

在同一個終端機視窗先執行；重開終端機時重新設定。在同一个终端窗口先执行，重开窗口后重新设置。Run this first in the same Terminal session; repeat after opening a new session.

```sh
GB_CLI="/Applications/GameBridge.app/Contents/Resources/WhiskyCmd"
test -x "$GB_CLI"
"$GB_CLI" --help
"$GB_CLI" runtime --help
```

`test -x` 成功時沒有輸出；檔案不存在時先確認 app 位置。`test -x` 成功时无输出；找不到文件时先检查应用位置。`test -x` is silent on success. If the file is missing, check the application location.

本機開發建置可改用以下路徑（在倉庫根目錄執行）。本地开发构建可改用以下路径（在仓库根目录执行）。For a local development build, use this instead from the repository root:

```sh
GB_CLI="$PWD/build/local/Build/Products/Debug/GameBridge.app/Contents/Resources/WhiskyCmd"
```

## 4. 查看引擎與環境 / 查看引擎与环境 / Inspect engines and environments

```sh
"$GB_CLI" runtime engines
"$GB_CLI" runtime environments
"$GB_CLI" runtime launch --help
```

輸出是 JSON。從環境記錄的 `id` 複製真正的 UUID，不要填環境名稱。输出为 JSON；从环境记录的 `id` 复制实际 UUID，不要填写环境名称。Output is JSON; use the environment record's actual `id`, not its display name.

```sh
GB_ENV_ID="REPLACE_WITH_ENVIRONMENT_ID"
```

先替換佔位文字再執行下方操作。先替换占位文字再执行下面的操作。Replace the placeholder before running the following commands.

## 5. 首次準備 / 首次准备 / First-time preparation

先在 app 閱讀完整 Microsoft 元件條款；只有接受後才使用以下旗標。此指令會下載及安裝元件，需要內建 bootstrap 資源，並非唯讀檢查。

先在应用中阅读完整 Microsoft 组件条款；接受后才使用以下标志。此命令会下载并安装组件，需要内置 bootstrap 资源，不是只读检查。

Read the complete Microsoft component terms in the app first. Use this flag only after accepting them. This command downloads and installs components and requires bundled bootstrap resources; it is not a read-only check.

```sh
"$GB_CLI" runtime bootstrap --accept-component-licenses
```

CLI 完成準備後，重新列出環境並用下一節指令啟動 Steam；GUI 一鍵流程會另行啟動 Steam。CLI 完成后，重新列出环境并用下一节命令启动 Steam；GUI 一键流程会另行启动 Steam。After CLI preparation, list environments again and launch Steam as below. The GUI adds the Steam launch after preparation.

重試使用相同指令；不要為一般重試加 `--new-environment`，該旗標會建立另一個環境。重试用相同命令，不要加 `--new-environment`，否则会建立另一个环境。Retry with the same command; `--new-environment` deliberately creates another environment and is not needed for an ordinary retry.

## 6. 啟動 Steam / 启动 Steam / Launch Steam

```sh
"$GB_CLI" runtime launch --environment "$GB_ENV_ID"
```

指令可能在 Steam 執行期間持續輸出記錄，並未必立即返回提示符。先正常退出遊戲，再從 Windows Steam 選「Steam → 結束」，不要只關閉視窗。

Steam 运行时命令可能持续输出日志，不会立即返回提示符。先正常退出游戏，再从 Windows Steam 选择“Steam → 退出”，不要只关闭窗口。

The command may remain active and stream logs while Steam runs. Exit the game, then choose **Steam → Exit** inside Windows Steam; closing its window alone may leave it running.

## 7. 恢復與重新辨識 / 恢复与重新识别 / Recover and re-register

以下每個操作按需要**單獨選用**，不是依次執行的修復腳本。先退出該環境的遊戲與 Steam。

以下操作按需要**单独选用**，不是按顺序执行的修复脚本。先退出该环境的游戏和 Steam。

Choose each operation **individually as needed**, not as a sequence to run blindly. Exit games and Steam in that environment first.

狀態恢復／状态恢复／Recover interrupted state (does not restore saves):

```sh
"$GB_CLI" runtime recover --environment "$GB_ENV_ID"
```

Steam 已在預設位置安裝但尚未登記／Steam 已在默认位置安装但尚未登记／Register Steam already installed at its default container path:

```sh
"$GB_CLI" runtime attach-steam --environment "$GB_ENV_ID"
```

移除前記下環境 ID；此操作保留檔案、不釋放磁碟空間／移除前记下 ID，此操作保留文件／Record the ID first; archive retains files and does not free disk space:

```sh
"$GB_CLI" runtime archive-environment --environment "$GB_ENV_ID"
```

還原已移除環境／还原已移除环境／Restore an archived environment:

```sh
"$GB_CLI" runtime restore-environment --environment "$GB_ENV_ID"
```

不要以舊版頂層 `delete` 取代 `runtime archive-environment`：它們是不同的容器流程，`delete` 會刪除舊版 bottle 檔案。不要用旧版顶层 `delete` 替代归档命令，它会删除旧版 bottle 文件。Do not substitute the legacy top-level `delete` command: it uses the legacy bottle workflow and deletes files.

## 8. 收集記錄 / 收集日志 / Capture logs

只在環境未執行時啟動下列一次；執行期間記錄會寫入桌面檔案。仅在环境未运行时执行，日志会写入桌面文件。Run once while the environment is idle; logs are written to a file on your Desktop.

```sh
GB_LOG="$HOME/Desktop/gamebridge-launch-$(date +%Y%m%d-%H%M%S).log"
"$GB_CLI" runtime launch --environment "$GB_ENV_ID" > "$GB_LOG" 2>&1
```

退出 Steam 後再查看檔案。分享前遮蓋帳號資料、私人路徑及 token；不要上傳整個容器。退出 Steam 后再检查文件；分享前隐藏账号、私人路径与 token。Review the file after exiting Steam and redact account details, private paths and tokens before sharing. Never upload the whole container.

## 9. 開發者建置 / 开发者构建 / Developer build

需要 Xcode、Command Line Tools 與 Apple Silicon Mac。以下會下載倉庫和建置依賴；若已有 checkout，直接進入其根目錄，不要重複 clone。

需要 Xcode、Command Line Tools 和 Apple Silicon Mac。已有 checkout 时直接进入根目录，不要重复 clone。

Requires Xcode, Command Line Tools and Apple Silicon. This downloads source and build dependencies. If you already have a checkout, enter its root instead of cloning again.

```sh
git clone https://github.com/enoswong/GameBridge.git
cd GameBridge
xcodebuild -resolvePackageDependencies \
  -project Whisky.xcodeproj \
  -scheme Whisky \
  -clonedSourcePackagesDirPath build/baseline/SourcePackages
swift test --package-path WhiskyKit
bash scripts/build-local.sh
open build/local/Build/Products/Debug/GameBridge.app
```

建置成功仍不代表附有 bootstrap 引擎。构建成功不代表包含 bootstrap 引擎。A successful app build does not supply the bootstrap runtime. See [release status](release/STATUS.md).

## 10. Windows CMD 呢？ / Windows CMD 呢？ / What about Windows CMD?

目前一般設定不需要 Windows CMD，受管理 CLI 也沒有通用 `runtime cmd` 子命令。不要在 Windows CMD 貼上本頁的 macOS 指令，亦不要直接以另一套 Wine 啟動容器，以免略過 GameBridge 的環境管理及相容性設定。特定 Windows 程式需要額外指令時，應先確認目標容器和引擎，再提供對應步驟。

目前普通设置不需要 Windows CMD，受管理 CLI 也没有通用 `runtime cmd` 子命令。不要在 Windows CMD 粘贴本页的 macOS 命令，也不要用另一套 Wine 直接启动容器。特定程序需要额外命令时，应先确认目标容器和引擎。

Normal setup does not require Windows CMD, and the managed CLI has no generic `runtime cmd` subcommand. Do not paste these macOS commands into Windows CMD or launch the container through an unrelated Wine installation, bypassing GameBridge's management and compatibility settings. Program-specific Windows commands require instructions matched to the actual container and engine.
