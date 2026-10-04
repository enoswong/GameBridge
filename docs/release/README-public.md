# GameBridge

**繁體中文** · [简体中文](https://github.com/enoswong/GameBridge/blob/main/docs/i18n/README.zh-CN.md) · [English](https://github.com/enoswong/GameBridge/blob/main/docs/i18n/README.en.md) · [指令教學 / Commands](https://github.com/enoswong/GameBridge/blob/main/docs/COMMANDS.md)

GameBridge 是基於 [Whisky](https://github.com/Whisky-App/Whisky) 開發的 macOS Windows 遊戲執行與環境管理工具，為 Apple Silicon Mac 提供 Windows Steam 設定、獨立容器與遊戲相容性處理。

目標是讓你透過一次設定，準備 Windows Steam、必要元件及適用的相容性修正，之後直接從 GameBridge 開啟 Steam 安裝和遊玩 Windows 遊戲。

> **目前下載狀態（2026-10-04）：GitHub 已提供源碼預覽版，完整應用程式安裝包尚未公開上架。** 下方操作教學適用於附有一鍵設定資源的 GameBridge 測試包。只有源碼或沒有執行引擎的自行建置版本，不能直接完成整套安裝。
>
> 預定公開測試包採用**未經 Apple Developer ID 簽署及公證**的發佈方式。引擎來源、第三方授權及公開套件驗證仍在整理；請以 [Releases](https://github.com/enoswong/GameBridge/releases) 實際提供的資產和版本說明為準。

## 目錄

- [主要功能](#主要功能)
- [使用前準備](#使用前準備)
- [下載與安裝](#下載與安裝)
- [首次一鍵設定](#首次一鍵設定)
- [安裝與遊玩 Windows 遊戲](#安裝與遊玩-windows-遊戲)
- [日常啟動與退出](#日常啟動與退出)
- [容器管理與資料位置](#容器管理與資料位置)
- [更新與備份](#更新與備份)
- [常見問題](#常見問題)
- [指令教學](#指令教學)
- [回報問題](#回報問題)
- [開發者建置](#開發者建置)
- [來源與授權](#來源與授權)

## 主要功能

| 功能 | 用途 |
| --- | --- |
| Windows Steam 一鍵準備 | 建立環境、驗證引擎、下載及安裝必要元件，再開啟 Windows Steam |
| 獨立 Windows 容器 | 各環境有自己的 Windows 檔案、程式、登錄資料及元件 |
| 圖形與輸入相容性 | 為支援的引擎和遊戲套用 DXMT／DirectX 11、DLL 載入、透明視窗及滑鼠修正 |
| 既有環境修正 | 從正常啟動流程補齊適用的內建相容性元件 |
| 安裝進度保留 | 安裝中斷後重試，依已完成的階段繼續 |
| 環境管理 | 顯示檔案位置、恢復狀態、移除及還原環境 |
| 執行記錄 | 在介面查看設定或啟動失敗的訊息 |

相容性修正有適用範圍，不會保證所有 Windows 遊戲都能執行。已完成開發機上的乾淨資料目錄設定及部分實際遊戲驗證；第二台實體 Mac 尚未完成驗收。

## 使用前準備

- **Apple Silicon Mac**：使用 Apple M 系列晶片；目前流程不以 Intel Mac 為支援目標。
- **macOS 15 或以上**：這是目前應用程式的最低建置目標；個別系統版本與遊戲相容性仍需驗證。
- **Rosetta**：執行目前的 Windows 相容引擎所需。GameBridge 尚未自動安裝 Rosetta；若 macOS 顯示安裝提示，依提示完成。可參考 [Apple 的 Rosetta 說明](https://support.apple.com/zh-hk/102527)。
- **本機 APFS 儲存空間**：環境需放在支援的本機磁碟，並預留引擎、Windows 元件、Steam、遊戲及更新所需空間。
- **網絡連線與 Steam 帳號**：首次設定會下載官方元件，遊戲下載、登入及 Steam Guard 驗證由 Steam 處理。

不需要另外安裝完整 Windows 系統。已有 macOS 版 Steam 的用戶，仍需在 GameBridge 內設定 **Windows 版 Steam**。

## 下載與安裝

### 1. 選擇正確下載項目

前往 [GameBridge Releases](https://github.com/enoswong/GameBridge/releases)，先閱讀該版本說明，再下載明確標示為應用程式的壓縮包。

目前的 `GameBridge-public-source.zip`、GitHub 自動提供的 `Source code (zip)` 和 `Source code (tar.gz)` 都是**源碼**，不包含可直接拖入「應用程式」使用的完整發行包。若該版本沒有應用程式資產，表示安裝包尚未上架。

### 2. 安裝應用程式

取得應用程式包後：

1. 解壓縮下載的檔案。
2. 將 `GameBridge.app` 拖到 Finder 的「應用程式」資料夾。
3. 從「應用程式」開啟 GameBridge。
4. 如系統要求 Rosetta 或存取你選取的檔案位置，按實際用途完成相關提示。

若版本說明附有 SHA-256，你可以在「終端機」輸入 `shasum -a 256 `（最後保留空格），將下載的壓縮檔拖入視窗，再按 Return，比對輸出的雜湊值。

### 3. 未公證版本首次開啟

若出現「無法驗證開發者」或「Apple 無法檢查 app」的提示，先確認下載來自本專案 Release，並核對該版本檔案：

1. 嘗試開啟 GameBridge 一次。
2. 開啟「系統設定 → 私隱與保安」。
3. 找到與 GameBridge 有關的提示，按「強制開啟／仍要打開」（名稱依系統語言而異）。
4. 在後續確認視窗選擇「開啟」。

這是針對該 app 的例外設定，毋須關閉整部 Mac 的保安檢查。若提示檔案損壞或含惡意內容，先重新下載、核對檔案並回報，不要當作一般未公證提示處理。詳見 [Apple 開啟未公證 app 的說明](https://support.apple.com/zh-hk/102445)。

## 首次一鍵設定

在 GameBridge 的 **「GameBridge · Windows Steam」** 設定畫面：

1. 在「首次使用」區域按 **「閱讀 Microsoft 元件條款」**。
2. 閱讀後，如接受條款，勾選 **「我已閱讀並接受 Microsoft 元件授權條款」**。
3. 按 **「一鍵準備 Windows Steam」**。
4. 等候執行記錄更新；期間保持網絡連線，不要移動環境資料夾或重複啟動安裝。
5. 完成後 Windows Steam 會開啟；依 Steam 提示完成更新、登入及帳號驗證。

這個流程會準備：

- 經完整性驗證的執行引擎及獨立 Windows 環境。
- Microsoft Visual C++ x64／x86 執行元件。
- DirectX June 2010 必要元件。
- Windows Steam。
- 與環境及目標遊戲相符的內建相容性修正。

Microsoft 元件與 Steam 安裝程式會從官方來源下載並檢查雜湊值；登入、購買遊戲及必要的發行商確認仍由你完成。遊戲自身的額外依賴可能仍需另行安裝。

**安裝中斷時：**查看「執行記錄」，排除網絡或空間問題後，再按一鍵準備重試。流程會依已記錄的完成階段繼續。若環境仍被 Steam 使用，先正常退出 Steam。

**看不到「首次使用」區域時：**目前 app 可能沒有內建設定資源。只有源碼建置成功不代表已有完整引擎；請核對下載版本，而不是反覆建立空環境。

## 安裝與遊玩 Windows 遊戲

1. 在 GameBridge 選擇已完成設定的「Windows 環境」。
2. 按 **「開啟 Windows Steam」**。
3. 在這個 Steam 視窗登入自己的帳號，前往收藏庫。
4. 選擇遊戲，按 Steam 的「安裝」，先使用該環境內的預設安裝位置。
5. 等待下載與遊戲必要元件安裝完成，再按「開始遊戲」。

**請使用 GameBridge 開啟的 Windows Steam 安裝 Windows 版本。** macOS Steam 已下載的 Mac 版遊戲不會自動變成 Windows 版。即使同一遊戲同時提供 Mac／Windows 版本，也應確認是在 Windows Steam 內安裝和啟動。

目前部分自動相容性修正只支援環境內的 `C:` 遊戲路徑。首次使用請保留預設 Steam 收藏庫位置；外置或自訂收藏庫尚未涵蓋完整修正流程。

首次測試時，依次確認遊戲能啟動、場景能顯示、鍵盤滑鼠能控制，以及存檔和退出是否正常。單純出現遊戲視窗不代表所有功能已通過驗證。

## 日常啟動與退出

以後遊玩毋須重新安裝：

1. 開啟 GameBridge。
2. 在側邊欄或「Windows 環境」選單選擇原本安裝遊戲的環境。
3. 按「開啟 Windows Steam」，再從 Steam 收藏庫啟動遊戲。

結束時先在遊戲內存檔並退出，再從 **Windows Steam 的「Steam → 結束」** 退出。只關閉 Steam 視窗，程式可能仍在背景執行。

更新 GameBridge、移除環境或恢復狀態前，也應先完成上述退出流程。建議保留正常的 GameBridge → Windows Steam → 遊戲啟動方式，讓適用的相容性設定一併載入。

## 容器管理與資料位置

「Windows 環境」亦稱容器或 Wine prefix。**每個容器的已安裝元件與遊戲是獨立的**；在 A 容器安裝 DLL，不會自動套用至 B 容器。

| 介面操作 | 功能與使用時機 |
| --- | --- |
| 建立 Windows 環境 | 使用「建立環境的引擎」及指定名稱建立另一個環境；這個按鈕本身不等於完整一鍵設定 |
| 初始化 | 準備剛建立環境的 Windows 基本檔案 |
| 安裝 Windows Steam… | 手動選取官方 `SteamSetup.exe`，安裝到目前選取的環境；不是選取 Mac 的 Steam.app |
| 辨識已安裝的 Steam | 在目前環境已安裝 Steam、但尚未登記時重新辨識 |
| 開啟 Windows Steam | 啟動目前選取環境的 Windows Steam |
| 在 Finder 顯示 | 定位目前容器的實際資料夾 |
| 恢復環境狀態 | 程式意外中斷、環境顯示需恢復時，檢查並恢復可操作狀態；不會回復遊戲存檔 |
| 移除環境… | 從使用清單移除環境，保留其檔案供日後恢復 |
| 重新整理 | 重新讀取環境與引擎狀態 |

「建立環境的引擎」影響新環境；既有環境實際綁定的版本以 **「目前環境引擎」** 為準。切換建立用選單不會自動更換既有環境的引擎。

### 找到遊戲檔案

按「在 Finder 顯示」定位容器，進入其 `drive_c` 即可查看虛擬 Windows `C:` 磁碟。Steam 預設遊戲目錄通常在 `drive_c/Program Files (x86)/Steam/steamapps/common`；實際路徑以 Steam 的安裝設定為準。亦可在 Windows Steam 的遊戲管理功能中瀏覽本機檔案。

Windows 安裝視窗中的 `C:` 是容器磁碟，不是 macOS「應用程式」資料夾。如果檔案選擇器回到根目錄，安裝 Steam 時請回到你下載 `SteamSetup.exe` 的資料夾；瀏覽已安裝遊戲則從容器的 `drive_c` 開始。

### 移除與恢復

1. 先退出該環境內的遊戲及 Windows Steam。
2. 選擇環境，按「移除環境…」並確認。
3. 要還原時，展開 **「已移除的環境（可恢復）」**，在該環境旁按「恢復」。

**目前移除操作不會刪除遊戲或存檔，因此也不會釋放它們佔用的磁碟空間。** 介面尚未提供永久清除教學流程，請勿為了騰出空間而直接刪除不確定用途的容器資料。

## 更新與備份

1. 在遊戲內存檔；如使用 Steam Cloud，確認 Steam 已完成同步。
2. 退出遊戲及 Windows Steam，再退出 GameBridge。
3. 需要本機備份時，先用「在 Finder 顯示」記下容器位置，待環境停止後複製整個容器到自己的備份磁碟。這份副本是資料備份，不代表已有跨機一鍵匯入功能。
4. 下載新版應用程式包並核對版本說明，替換「應用程式」內的 GameBridge.app。
5. 重新開啟，選擇既有環境，再以「開啟 Windows Steam」啟動。

適用的內建相容性元件會在正常啟動時檢查及補齊；這不代表所有引擎、所有自訂 DLL 或所有外置遊戲路徑都會自動遷移。

容器備份可能包含你的 Steam 登入狀態、個人設定、遊戲及存檔，請私人保存。專案的公開源碼與發行包不包含開發者的 Steam 帳號或個人容器。

## 常見問題

| 問題 | 處理方式 |
| --- | --- |
| 下載後只有程式碼，沒有 app | 你下載的是源碼包。到 Releases 確認是否已有應用程式資產；目前公開版本仍是源碼預覽 |
| 沒有一鍵準備按鈕／顯示沒有已驗證引擎 | 檢查是否使用包含設定資源的版本。一般源碼建置不會自動提供完整執行引擎 |
| 一鍵準備按鈕不能按 | 先閱讀並接受 Microsoft 元件條款，並確認沒有另一個準備作業正在執行 |
| 安裝下載失敗或雜湊不符 | 檢查網絡、磁碟空間及執行記錄；重試仍失敗便回報。不要自行略過驗證或換入來源不明的 DLL |
| 新容器缺少之前安裝的 DLL | 元件是按容器安裝。確認使用完成一鍵設定的環境；單按「建立 Windows 環境」不會複製舊容器的元件 |
| 遊戲提示缺少 Visual C++ | 確認遊戲位於完成必要元件安裝的同一環境。仍出錯時記錄完整提示及環境引擎版本 |
| Steam 已安裝但無法開啟 | 核對所選環境，必要時使用「辨識已安裝的 Steam」，再查看執行記錄 |
| Steam 沒有畫面／steamwebhelper.exe 出錯 | 正常退出 Windows Steam；停止後如環境需要恢復，按「恢復環境狀態」。重開仍失敗時回報記錄，不要反覆重裝所有容器 |
| 容器看不見 | 按「重新整理」，再查看「已移除的環境（可恢復）」 |
| 移除按鈕停用或無法移除 | 確認遊戲與 Steam 已結束；若顯示需恢復，先恢復環境狀態。執行中的環境不能移除 |
| 有場景但無法點擊／透明顯示不正常 | 先確認使用最新測試包、正確容器及正常啟動流程，遊戲安裝在環境內的 C:。仍有問題請回報，不必先修改遊戲檔案 |
| 想把其他環境或整套 DLL 直接搬過來 | 引擎、登錄資料與元件版本可能不同。保留原環境，先使用受支援的設定流程，不要整套覆蓋系統 DLL |

DirectX June 2010 元件安裝與 DXMT 圖形轉譯是不同步驟；「缺少圖形功能」不一定能靠重裝 DirectX 解決。反作弊、DRM、影片播放或其他遊戲依賴的支援程度，也需要按遊戲實測。

## 指令教學

一般使用毋須輸入指令。需要檢查版本、列出環境、啟動 Steam、恢復狀態或建置源碼時，請參閱[繁中／簡中／英文指令教學](https://github.com/enoswong/GameBridge/blob/main/docs/COMMANDS.md)。指令在 macOS「終端機」執行，不是 Windows CMD；文件翻譯不代表 app 介面已翻譯。

## 回報問題

請到 [GitHub Issues](https://github.com/enoswong/GameBridge/issues) 提供：

- GameBridge 版本，以及下載包名稱或源碼 commit。
- Mac 晶片型號、macOS 版本。
- 選取的環境名稱、介面顯示的實際引擎版本。
- 出問題的階段：首次設定、Steam 登入、下載、遊戲啟動、圖形或輸入。
- 重現步驟、錯誤訊息、經遮蓋個人資料的截圖或相關執行記錄片段。

不要上傳完整容器、Steam 登入檔、Steam Guard 驗證碼、帳號 token 或整個個人資料夾。分享記錄前請遮蓋帳號識別資料及私人路徑。

## 開發者建置

需要 Apple Silicon Mac、相容的 Xcode 與 Command Line Tools。在本倉庫根目錄執行：

```sh
swift test --package-path WhiskyKit
bash scripts/build-local.sh
```

本機建置輸出為 `build/local/Build/Products/Debug/GameBridge.app`。建置腳本使用固定的套件解析設定；若依賴尚未下載，先依[指令教學](https://github.com/enoswong/GameBridge/blob/main/docs/COMMANDS.md)將套件解析到建置腳本使用的目錄，再執行建置。

此腳本產生未簽署 Debug 版本，不代表完整公開發行包。Bootstrap 引擎資源需另外準備；詳見 [發佈狀態](https://github.com/enoswong/GameBridge/blob/main/docs/release/STATUS.md) 與 [引擎來源核對報告](https://github.com/enoswong/GameBridge/blob/main/docs/release/RUNTIME-AUDIT-2026-10-04.md)。

## 來源與授權

本專案基於 Whisky commit `fd5480a76b3ebfe3419a1ab86ca3695f5cc328f8`，保留原有 [GPL-3.0-or-later 授權](https://github.com/enoswong/GameBridge/blob/main/LICENSE)、版權說明與 Git 歷史。GameBridge 新增的應用程式與相容層源碼亦以 GPL-3.0-or-later 提供；各第三方元件依其本身授權處理。

感謝 Whisky、Wine、DXMT 及相關開源專案的工作。Whisky、Wine、DXMT、Steam、Microsoft 與 Apple 名稱屬各自專案或權利人；GameBridge 並非其官方發行版本。
