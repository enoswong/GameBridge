# GameBridge

GameBridge 是基於 [Whisky](https://github.com/Whisky-App/Whisky) 的 Apple Silicon macOS Windows 遊戲執行與環境管理專案，保留原專案的 GPL-3.0-or-later 授權及來源歷史。

## 功能

- Windows Steam 一鍵準備：環境建立、官方必要元件下載、完整性驗證與安裝。
- 獨立 Windows 容器管理、Steam 啟動、移除與恢復。
- 內建適用的圖形、透明視窗、滑鼠輸入及 DLL 載入相容性設定。
- 啟動既有環境時自動補齊內建相容性元件。
- 安裝中斷後重試、執行記錄及環境狀態恢復。

## 版本狀態

目前是開發預覽版。已在開發機完成乾淨資料目錄的必要元件安裝驗證，並驗證既有環境的自動修正與實際遊戲輸入／透明效果。不同遊戲仍需個別驗證，第二台實體 Mac 尚未驗收。

公開源碼不包含 Steam 帳號、登入 session、Wine prefix、遊戲、存檔、快取或本機執行記錄。Microsoft 元件與 Steam 安裝程式由官方來源下載，不在源碼庫中重新分發。

目前約 435 MB 的本機預覽包含有標記為 internalOnly 的研究執行引擎，**尚未批准為公開 Release 資產**。引擎及其依賴的精確來源／授權整理、正式 catalog 信任根、Developer ID 簽署與公證仍待完成。本倉庫不把該包標示為可公開發佈的完整版。

## 建置與測試

需要 Apple Silicon Mac、Xcode 及命令列工具。測試：

```sh
swift test --package-path WhiskyKit
```

本機 Debug 建置：

```sh
bash scripts/build-local.sh
```

未準備 Bootstrap payload 時，可建置源碼及管理介面，但不提供完整的一鍵引擎安裝。執行引擎封裝規格與公開發佈條件見 [發佈狀態](docs/release/STATUS.md)。

## 來源與授權

應用程式基於 Whisky commit `fd5480a76b3ebfe3419a1ab86ca3695f5cc328f8`。原有 LICENSE 與檔案版權說明保留。GameBridge 的新增應用程式與相容層源碼以 GPL-3.0-or-later 提供；個別第三方元件以各自授權為準。

Whisky、Wine、DXMT、Steam、Microsoft 及 Apple 的名稱屬各自專案或權利人，本專案並非其官方發行版本。
