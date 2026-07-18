# 纸羽轻阅（reader-ios）

本地优先的 iOS 阅读器。在 [阅小说开源 iOS 客户端](https://github.com/yuenov/reader-ios) 基础上，强化本地书导入、阅读体验、AI 翻译与备份能力；主界面以 **书架 + 设置** 为主，不再依赖在线书城作为默认路径。

| 项 | 说明 |
|----|------|
| 应用名 | **纸羽轻阅**（`CFBundleDisplayName`） |
| Bundle ID | `xyz.malu2335.reader` |
| 语言 | Objective-C |
| 最低系统 | iOS 15.0 |
| 设备 | 仅 iPhone |
| 依赖管理 | CocoaPods |
| 数据 | WCDB（SQLite）+ Keychain（AI 密钥） |
| 仓库 | https://github.com/malu2335/reader-ios |

---

## 界面预览

当前版本「纸羽轻阅」主要界面（图源见仓库 `Screenshots/`；App Store 全尺寸导出可放在本地 `AppStoreScreenshots/`，该目录默认不进 Git）。

| 书架 | 正文阅读 | 阅读工具 |
|:---:|:---:|:---:|
| <img src="Screenshots/01-bookshelf.png" width="180" alt="书架"/> | <img src="Screenshots/02-reading.png" width="180" alt="正文阅读"/> | <img src="Screenshots/03-reading-tools.png" width="180" alt="阅读工具"/> |
| 本地书封面网格 · 导入入口 | 纸色正文 · 进度与章节 | 目录 / 书签 / 亮度 / 字号 |

| 排版设置 | 应用设置 | 正文净化 |
|:---:|:---:|:---:|
| <img src="Screenshots/04-typography.png" width="180" alt="排版设置"/> | <img src="Screenshots/05-settings.png" width="180" alt="应用设置"/> | <img src="Screenshots/06-reading-rules.png" width="180" alt="正文净化"/> |
| 字号 · 字体 · 翻页动画 | 导入 · AI · 备份 · 隐私/开源入口 | legado 风格替换规则 |

| 隐私声明 | 开源软件使用声明 |
|:---:|:---:|
| <img src="Screenshots/07-privacy.png" width="180" alt="隐私声明"/> | <img src="Screenshots/08-opensource.png" width="180" alt="开源软件使用声明"/> |
| 设置内本地文档 | 完整许可与归属 · 可滚动复制 |

---

## 主要能力

### 本地阅读
- 导入 **TXT / EPUB / PDF / MOBI / ZIP / CBZ**，以及**包含图片的文件夹**（图集）
- 支持系统「用其他应用打开 / 分享」到纸羽轻阅（复制进沙盒，不修改源文件）
- ZIP/CBZ：按文件名自然序浏览图片（jpg/png/webp/gif 等）；文件夹会打包为 CBZ 再入库
- 章节解析与 WCDB 存储；`bookId < 0` 标识本地书，与遗留在线链路隔离
- 内容哈希去重导入提示
- 阅读进度（含字符偏移）、**书签**；漫画用页码进度
- 正文净化规则、系统词典查询
- 书架长按菜单、类型化分享卡片

### AI 翻译
- 多配置档案：OpenAI / Anthropic / Gemini 官方与兼容端点（自定义 Base URL）
- 阅读页句级翻译，译文**内嵌在原文下方**（非弹窗）
- **翻译模式**跨翻页保持；后台批量预译，关闭展示后仍可继续后台翻译
- **API Key 仅存 Keychain**；磁盘配置与备份 zip **不含明文密钥**
- 本地 HTTP 兼容端点需 ATS 例外（见设置中的自定义 Base URL）

### 朗读与设置
- 系统 `AVSpeech` 朗读条；语音选择、收藏、个人声音导入指引
- 自定义字体导入
- 备份 / 恢复（布局参考 Legado：`bookshelf.json` / `config.json` / `books/`，并含 AI 元数据）
- 设置内可查看**隐私声明**与**开源软件使用声明**（本地文本）

### 体验与工程
- UIScene 生命周期、启动页与书架预加载
- ProMotion / 高刷新相关路径
- 冷启动延后非关键初始化；设置页避免首点卡顿
- AI 协议与备份脱敏等可用 `Tests/AIHarness` 做本地 harness 校验

---

## 环境要求

- macOS + **Xcode**（建议较新版本；`Podfile` 含 Xcode 15+ / 新 clang 对 AFNetworking、YYText、WCDB 的补丁）
- [CocoaPods](https://cocoapods.org/)
- iOS **15.0+** 模拟器或真机（iPhone）

---

## 快速开始

```bash
git clone https://github.com/malu2335/reader-ios.git
cd reader-ios/Reader
pod install
open Reader.xcworkspace
```

在 Xcode 中选择 **Reader** scheme，目标选模拟器或真机，Run。

### 可选：本地 harness

```bash
cd Reader/Tests/AIHarness && ./run_tests.sh          # AI 协议 / 备份脱敏
cd Reader/Tests/ExternalImportHarness && ./run_tests.sh   # 外部文件导入
cd Reader/Tests/LegalDocumentsHarness && ./run_tests.sh   # 隐私/开源声明文档
```

### libwebp 下载失败

若 `pod install` 因访问 `chromium.googlesource.com` 超时，可将本地 Spec 中 libwebp 的 `source.git` 改为 GitHub 镜像后再装依赖：

```text
~/.cocoapods/repos/<主仓库>/Specs/1/9/2/libwebp/<版本>/libwebp.podspec.json
```

```json
"source": {
  "git": "https://github.com/webmproject/libwebp.git",
  "tag": "v1.1.0"
}
```

（版本号以 `Podfile.lock` 为准。）然后重新执行 `pod install`。

---

## 目录结构（摘要）

```text
reader-ios/
├── README.md
├── LICENSE                 # © 2020 阅小说；© 2026 Lu Ma / 纸羽轻阅
├── Screenshots/            # README 界面预览（已压缩，可提交）
├── AppStoreScreenshots/    # 本地 ASC 全尺寸导出（默认 gitignore）
└── Reader/
    ├── Podfile
    ├── Reader.xcodeproj
    ├── Reader.xcworkspace  # pod install 后打开此 workspace
    ├── Reader/             # 主工程源码
    │   ├── Application/    # AppDelegate / SceneDelegate
    │   ├── Common/AI/      # 多厂商翻译客户端与配置
    │   ├── Common/LocalBook/
    │   ├── Common/Speech/
    │   ├── Database/       # WCDB 模型与 Manager
    │   ├── Sections/       # 书架 / 阅读 / 设置等
    │   └── Resource/       # Info.plist、隐私/开源声明、图标
    └── Tests/              # AIHarness / ExternalImportHarness / LegalDocumentsHarness
```

---

## 隐私与密钥

- **不要**把真实 API Key、备份 zip、个人书库数据库、模拟器截图提交进 Git。
- AI Key：Keychain 服务名 `reader.ios.ai.apikey`；备份中的 `ai_config` 仅元数据（`apiKey` 为空）。
- 设置页可查看随包发布的隐私声明与开源许可全文。
- 商店全尺寸截图建议放在本地 `AppStoreScreenshots/`；README 使用仓库内 `Screenshots/`。
- 本地调试目录 `.cursor/`、`.DS_Store`、`docs/`、`CLAUDE.md`、根目录截图等已在 `.gitignore` 中忽略。
- 推送前建议自检：`git diff` / `git grep` 是否含 `sk-`、私钥、本机绝对路径等。

---

## 与上游的关系

本仓库基于阅小说 iOS 开源客户端演进，保留大量原工程结构与部分在线模块代码（发现 / 书库 / 搜索等历史模块仍在工程中，仅作历史追踪，默认产品路径为本地阅读 + AI 翻译）。

| 资源 | 链接 |
|------|------|
| 本仓库 | https://github.com/malu2335/reader-ios |
| 上游 iOS | https://github.com/yuenov/reader-ios |
| 上游 API 文档 | https://github.com/yuenov/reader-api |
| 上游 Android | https://github.com/yuenov/reader-android |

原「阅小说」产品与商店分发信息请以上游及官方渠道为准；本仓库为**独立维护的本地优先衍生版本**，应用展示名为 **纸羽轻阅**。

---

## 声明

- 上游服务侧能力以阅小说开源说明为准；本客户端强调**本地文件阅读**与用户自备 AI 服务。
- 请勿将本项目用于侵犯著作权或其他违法行为；用户导入的内容与配置的 AI 密钥由用户自行负责。
- 软件按 MIT 许可提供，详见 [LICENSE](LICENSE)。本衍生版本保留上游「阅小说」版权声明，并增加 2026 年 Lu Ma（纸羽轻阅）版权行。
