# GameBridge

[繁體中文](https://github.com/enoswong/GameBridge#readme) · **简体中文** · [English](README.en.md) · [命令指南 / Commands](../COMMANDS.md)

GameBridge 是基于 [Whisky](https://github.com/Whisky-App/Whisky) 开发的 macOS Windows 游戏执行与环境管理工具，为 Apple Silicon Mac 提供 Windows Steam 设定、独立容器与游戏相容性处理。

目标是让你透过一次设定，准备 Windows Steam、必要元件及适用的相容性修正，之后直接从 GameBridge 开启 Steam 安装和游玩 Windows 游戏。

> **目前下载状态（2026-10-04）：GitHub 已提供源码预览版，完整应用程式安装包尚未公开上架。** 下方操作教学适用于附有一键设定资源的 GameBridge 测试包。只有源码或没有执行引擎的自行建置版本，不能直接完成整套安装。
>
> 预定公开测试包采用**未经 Apple Developer ID 签署及公证**的发布方式。引擎来源、第三方授权及公开套件验证仍在整理；请以 [Releases](https://github.com/enoswong/GameBridge/releases) 实际提供的资产和版本说明为准。

## 目录

- [主要功能](#主要功能)
- [使用前准备](#使用前准备)
- [下载与安装](#下载与安装)
- [首次一键设定](#首次一键设定)
- [安装与游玩 Windows 游戏](#安装与游玩-windows-游戏)
- [日常启动与退出](#日常启动与退出)
- [容器管理与资料位置](#容器管理与资料位置)
- [更新与备份](#更新与备份)
- [常见问题](#常见问题)
- [指令教学](#指令教学)
- [回报问题](#回报问题)
- [开发者建置](#开发者建置)
- [来源与授权](#来源与授权)

## 主要功能

| 功能 | 用途 |
| --- | --- |
| Windows Steam 一键准备 | 建立环境、验证引擎、下载及安装必要元件，再开启 Windows Steam |
| 独立 Windows 容器 | 各环境有自己的 Windows 档案、程式、登录资料及元件 |
| 图形与输入相容性 | 为支援的引擎和游戏套用 DXMT／DirectX 11、DLL 载入、透明视窗及滑鼠修正 |
| 既有环境修正 | 从正常启动流程补齐适用的内建相容性元件 |
| 安装进度保留 | 安装中断后重试，依已完成的阶段继续 |
| 环境管理 | 显示档案位置、恢复状态、移除及还原环境 |
| 执行记录 | 在介面查看设定或启动失败的讯息 |

相容性修正有适用范围，不会保证所有 Windows 游戏都能执行。已完成开发机上的干净资料目录设定及部分实际游戏验证；第二台实体 Mac 尚未完成验收。

## 使用前准备

- **Apple Silicon Mac**：使用 Apple M 系列晶片；目前流程不以 Intel Mac 为支援目标。
- **macOS 15 或以上**：这是目前应用程式的最低建置目标；个别系统版本与游戏相容性仍需验证。
- **Rosetta**：执行目前的 Windows 相容引擎所需。GameBridge 尚未自动安装 Rosetta；若 macOS 显示安装提示，依提示完成。可参考 [Apple 的 Rosetta 说明](https://support.apple.com/zh-hk/102527)。
- **本机 APFS 储存空间**：环境需放在支援的本机磁碟，并预留引擎、Windows 元件、Steam、游戏及更新所需空间。
- **网络连线与 Steam 帐号**：首次设定会下载官方元件，游戏下载、登入及 Steam Guard 验证由 Steam 处理。

不需要另外安装完整 Windows 系统。已有 macOS 版 Steam 的用户，仍需在 GameBridge 内设定 **Windows 版 Steam**。

## 下载与安装

### 1. 选择正确下载项目

前往 [GameBridge Releases](https://github.com/enoswong/GameBridge/releases)，先阅读该版本说明，再下载明确标示为应用程式的压缩包。

目前的 `GameBridge-public-source.zip`、GitHub 自动提供的 `Source code (zip)` 和 `Source code (tar.gz)` 都是**源码**，不包含可直接拖入「应用程式」使用的完整发行包。若该版本没有应用程式资产，表示安装包尚未上架。

### 2. 安装应用程式

取得应用程式包后：

1. 解压缩下载的档案。
2. 将 `GameBridge.app` 拖到 Finder 的「应用程式」资料夹。
3. 从「应用程式」开启 GameBridge。
4. 如系统要求 Rosetta 或存取你选取的档案位置，按实际用途完成相关提示。

若版本说明附有 SHA-256，你可以在「终端机」输入 `shasum -a 256 `（最后保留空格），将下载的压缩档拖入视窗，再按 Return，比对输出的杂凑值。

### 3. 未公证版本首次开启

若出现「无法验证开发者」或「Apple 无法检查 app」的提示，先确认下载来自本专案 Release，并核对该版本档案：

1. 尝试开启 GameBridge 一次。
2. 开启「系统设定 → 私隐与保安」。
3. 找到与 GameBridge 有关的提示，按「强制开启／仍要打开」（名称依系统语言而异）。
4. 在后续确认视窗选择「开启」。

这是针对该 app 的例外设定，毋须关闭整部 Mac 的保安检查。若提示档案损坏或含恶意内容，先重新下载、核对档案并回报，不要当作一般未公证提示处理。详见 [Apple 开启未公证 app 的说明](https://support.apple.com/zh-hk/102445)。

## 首次一键设定

当前界面的按钮采用繁体中文，本指南使用简体对应名称；例如“开启 Windows Steam”对应界面上的“開啟 Windows Steam”。这份文档不会改变应用的界面语言。

在 GameBridge 的 **「GameBridge · Windows Steam」** 设定画面：

1. 在「首次使用」区域按 **「阅读 Microsoft 元件条款」**。
2. 阅读后，如接受条款，勾选 **「我已阅读并接受 Microsoft 元件授权条款」**。
3. 按 **「一键准备 Windows Steam」**。
4. 等候执行记录更新；期间保持网络连线，不要移动环境资料夹或重复启动安装。
5. 完成后 Windows Steam 会开启；依 Steam 提示完成更新、登入及帐号验证。

这个流程会准备：

- 经完整性验证的执行引擎及独立 Windows 环境。
- Microsoft Visual C++ x64／x86 执行元件。
- DirectX June 2010 必要元件。
- Windows Steam。
- 与环境及目标游戏相符的内建相容性修正。

Microsoft 元件与 Steam 安装程式会从官方来源下载并检查杂凑值；登入、购买游戏及必要的发行商确认仍由你完成。游戏自身的额外依赖可能仍需另行安装。

**安装中断时：**查看「执行记录」，排除网络或空间问题后，再按一键准备重试。流程会依已记录的完成阶段继续。若环境仍被 Steam 使用，先正常退出 Steam。

**看不到「首次使用」区域时：**目前 app 可能没有内建设定资源。只有源码建置成功不代表已有完整引擎；请核对下载版本，而不是反覆建立空环境。

## 安装与游玩 Windows 游戏

1. 在 GameBridge 选择已完成设定的「Windows 环境」。
2. 按 **「开启 Windows Steam」**。
3. 在这个 Steam 视窗登入自己的帐号，前往收藏库。
4. 选择游戏，按 Steam 的「安装」，先使用该环境内的预设安装位置。
5. 等待下载与游戏必要元件安装完成，再按「开始游戏」。

**请使用 GameBridge 开启的 Windows Steam 安装 Windows 版本。** macOS Steam 已下载的 Mac 版游戏不会自动变成 Windows 版。即使同一游戏同时提供 Mac／Windows 版本，也应确认是在 Windows Steam 内安装和启动。

目前部分自动相容性修正只支援环境内的 `C:` 游戏路径。首次使用请保留预设 Steam 收藏库位置；外置或自订收藏库尚未涵盖完整修正流程。

首次测试时，依次确认游戏能启动、场景能显示、键盘滑鼠能控制，以及存档和退出是否正常。单纯出现游戏视窗不代表所有功能已通过验证。

## 日常启动与退出

以后游玩毋须重新安装：

1. 开启 GameBridge。
2. 在侧边栏或「Windows 环境」选单选择原本安装游戏的环境。
3. 按「开启 Windows Steam」，再从 Steam 收藏库启动游戏。

结束时先在游戏内存档并退出，再从 **Windows Steam 的「Steam → 结束」** 退出。只关闭 Steam 视窗，程式可能仍在背景执行。

更新 GameBridge、移除环境或恢复状态前，也应先完成上述退出流程。建议保留正常的 GameBridge → Windows Steam → 游戏启动方式，让适用的相容性设定一并载入。

## 容器管理与资料位置

「Windows 环境」亦称容器或 Wine prefix。**每个容器的已安装元件与游戏是独立的**；在 A 容器安装 DLL，不会自动套用至 B 容器。

| 介面操作 | 功能与使用时机 |
| --- | --- |
| 建立 Windows 环境 | 使用「建立环境的引擎」及指定名称建立另一个环境；这个按钮本身不等于完整一键设定 |
| 初始化 | 准备刚建立环境的 Windows 基本档案 |
| 安装 Windows Steam… | 手动选取官方 `SteamSetup.exe`，安装到目前选取的环境；不是选取 Mac 的 Steam.app |
| 辨识已安装的 Steam | 在目前环境已安装 Steam、但尚未登记时重新辨识 |
| 开启 Windows Steam | 启动目前选取环境的 Windows Steam |
| 在 Finder 显示 | 定位目前容器的实际资料夹 |
| 恢复环境状态 | 程式意外中断、环境显示需恢复时，检查并恢复可操作状态；不会回复游戏存档 |
| 移除环境… | 从使用清单移除环境，保留其档案供日后恢复 |
| 重新整理 | 重新读取环境与引擎状态 |

「建立环境的引擎」影响新环境；既有环境实际绑定的版本以 **「目前环境引擎」** 为准。切换建立用选单不会自动更换既有环境的引擎。

### 找到游戏档案

按「在 Finder 显示」定位容器，进入其 `drive_c` 即可查看虚拟 Windows `C:` 磁碟。Steam 预设游戏目录通常在 `drive_c/Program Files (x86)/Steam/steamapps/common`；实际路径以 Steam 的安装设定为准。亦可在 Windows Steam 的游戏管理功能中浏览本机档案。

Windows 安装视窗中的 `C:` 是容器磁碟，不是 macOS「应用程式」资料夹。如果档案选择器回到根目录，安装 Steam 时请回到你下载 `SteamSetup.exe` 的资料夹；浏览已安装游戏则从容器的 `drive_c` 开始。

### 移除与恢复

1. 先退出该环境内的游戏及 Windows Steam。
2. 选择环境，按「移除环境…」并确认。
3. 要还原时，展开 **「已移除的环境（可恢复）」**，在该环境旁按「恢复」。

**目前移除操作不会删除游戏或存档，因此也不会释放它们占用的磁碟空间。** 介面尚未提供永久清除教学流程，请勿为了腾出空间而直接删除不确定用途的容器资料。

## 更新与备份

1. 在游戏内存档；如使用 Steam Cloud，确认 Steam 已完成同步。
2. 退出游戏及 Windows Steam，再退出 GameBridge。
3. 需要本机备份时，先用「在 Finder 显示」记下容器位置，待环境停止后复制整个容器到自己的备份磁碟。这份副本是资料备份，不代表已有跨机一键汇入功能。
4. 下载新版应用程式包并核对版本说明，替换「应用程式」内的 GameBridge.app。
5. 重新开启，选择既有环境，再以「开启 Windows Steam」启动。

适用的内建相容性元件会在正常启动时检查及补齐；这不代表所有引擎、所有自订 DLL 或所有外置游戏路径都会自动迁移。

容器备份可能包含你的 Steam 登入状态、个人设定、游戏及存档，请私人保存。专案的公开源码与发行包不包含开发者的 Steam 帐号或个人容器。

## 常见问题

| 问题 | 处理方式 |
| --- | --- |
| 下载后只有程式码，没有 app | 你下载的是源码包。到 Releases 确认是否已有应用程式资产；目前公开版本仍是源码预览 |
| 没有一键准备按钮／显示没有已验证引擎 | 检查是否使用包含设定资源的版本。一般源码建置不会自动提供完整执行引擎 |
| 一键准备按钮不能按 | 先阅读并接受 Microsoft 元件条款，并确认没有另一个准备作业正在执行 |
| 安装下载失败或杂凑不符 | 检查网络、磁碟空间及执行记录；重试仍失败便回报。不要自行略过验证或换入来源不明的 DLL |
| 新容器缺少之前安装的 DLL | 元件是按容器安装。确认使用完成一键设定的环境；单按「建立 Windows 环境」不会复制旧容器的元件 |
| 游戏提示缺少 Visual C++ | 确认游戏位于完成必要元件安装的同一环境。仍出错时记录完整提示及环境引擎版本 |
| Steam 已安装但无法开启 | 核对所选环境，必要时使用「辨识已安装的 Steam」，再查看执行记录 |
| Steam 没有画面／steamwebhelper.exe 出错 | 正常退出 Windows Steam；停止后如环境需要恢复，按「恢复环境状态」。重开仍失败时回报记录，不要反覆重装所有容器 |
| 容器看不见 | 按「重新整理」，再查看「已移除的环境（可恢复）」 |
| 移除按钮停用或无法移除 | 确认游戏与 Steam 已结束；若显示需恢复，先恢复环境状态。执行中的环境不能移除 |
| 有场景但无法点击／透明显示不正常 | 先确认使用最新测试包、正确容器及正常启动流程，游戏安装在环境内的 C:。仍有问题请回报，不必先修改游戏档案 |
| 想把其他环境或整套 DLL 直接搬过来 | 引擎、登录资料与元件版本可能不同。保留原环境，先使用受支援的设定流程，不要整套覆盖系统 DLL |

DirectX June 2010 元件安装与 DXMT 图形转译是不同步骤；「缺少图形功能」不一定能靠重装 DirectX 解决。反作弊、DRM、影片播放或其他游戏依赖的支援程度，也需要按游戏实测。

## 指令教学

一般使用毋须输入指令。需要检查版本、列出环境、启动 Steam、恢复状态或建置源码时，请参阅[繁中／简中／英文指令教学](https://github.com/enoswong/GameBridge/blob/main/docs/COMMANDS.md)。指令在 macOS「终端机」执行，不是 Windows CMD；文件翻译不代表 app 介面已翻译。

## 回报问题

请到 [GitHub Issues](https://github.com/enoswong/GameBridge/issues) 提供：

- GameBridge 版本，以及下载包名称或源码 commit。
- Mac 晶片型号、macOS 版本。
- 选取的环境名称、介面显示的实际引擎版本。
- 出问题的阶段：首次设定、Steam 登入、下载、游戏启动、图形或输入。
- 重现步骤、错误讯息、经遮盖个人资料的截图或相关执行记录片段。

不要上传完整容器、Steam 登入档、Steam Guard 验证码、帐号 token 或整个个人资料夹。分享记录前请遮盖帐号识别资料及私人路径。

## 开发者建置

需要 Apple Silicon Mac、相容的 Xcode 与 Command Line Tools。在本仓库根目录执行：

```sh
swift test --package-path WhiskyKit
bash scripts/build-local.sh
```

本机建置输出为 `build/local/Build/Products/Debug/GameBridge.app`。建置脚本使用固定的套件解析设定；若依赖尚未下载，先依[指令教学](https://github.com/enoswong/GameBridge/blob/main/docs/COMMANDS.md)将套件解析到建置脚本使用的目录，再执行建置。

此脚本产生未签署 Debug 版本，不代表完整公开发行包。Bootstrap 引擎资源需另外准备；详见 [发布状态](https://github.com/enoswong/GameBridge/blob/main/docs/release/STATUS.md) 与 [引擎来源核对报告](https://github.com/enoswong/GameBridge/blob/main/docs/release/RUNTIME-AUDIT-2026-10-04.md)。

## 来源与授权

本专案基于 Whisky commit `fd5480a76b3ebfe3419a1ab86ca3695f5cc328f8`，保留原有 [GPL-3.0-or-later 授权](https://github.com/enoswong/GameBridge/blob/main/LICENSE)、版权说明与 Git 历史。GameBridge 新增的应用程式与相容层源码亦以 GPL-3.0-or-later 提供；各第三方元件依其本身授权处理。

感谢 Whisky、Wine、DXMT 及相关开源专案的工作。Whisky、Wine、DXMT、Steam、Microsoft 与 Apple 名称属各自专案或权利人；GameBridge 并非其官方发行版本。
