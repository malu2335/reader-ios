# 轻阅（reader-ios）

本地优先的 iOS 阅读器。在 [阅小说开源 iOS 客户端](https://github.com/yuenov/reader-ios) 基础上，强化本地书导入、阅读体验、AI 翻译与备份能力；主界面以 **书架 + 设置** 为主，不再依赖在线书城作为默认路径。

| 项 | 说明 |
|----|------|
| 应用名 | **轻阅**（`CFBundleDisplayName`） |
| Bundle ID | `xyz.malu2335.reader` |
| 语言 | Objective-C |
| 最低系统 | iOS 15.0 |
| 依赖管理 | CocoaPods |
| 数据 | WCDB（SQLite）+ Keychain（AI 密钥） |
| 仓库 | https://github.com/malu2335/reader-ios |

---

## 主要能力

### 本地阅读
- 导入 **TXT / EPUB / PDF / MOBI**（系统文档选择器 / 打开方式）
- 章节解析与 WCDB 存储；`bookId < 0` 标识本地书，与在线链路隔离
- 内容哈希去重导入提示
- 阅读进度（含字符偏移）、**书签**
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

### 体验与工程
- UIScene 生命周期、启动页与书架预加载
- ProMotion / 高刷新相关路径
- 冷启动延后非关键初始化；设置页避免首点卡顿
- AI 协议与备份脱敏等可用 `Tests/AIHarness` 做本地 harness 校验

---

## 环境要求

- macOS + **Xcode**（建议较新版本；`Podfile` 含 Xcode 15+ / 新 clang 对 AFNetworking、YYText、WCDB 的补丁）
- [CocoaPods](https://cocoapods.org/)
- iOS **15.0+** 模拟器或真机

---

## 快速开始

```bash
git clone https://github.com/malu2335/reader-ios.git
cd reader-ios/Reader
pod install
open Reader.xcworkspace
```

在 Xcode 中选择 **Reader** scheme，目标选模拟器或真机，Run。

### 可选：AI 协议 harness

```bash
cd Reader/Tests/AIHarness
./run_tests.sh
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
├── LICENSE                 # 原项目 MIT（© 2020 阅小说）
├── docs/                   # 审查与设计类文档
├── resource/               # 历史界面预览图
└── Reader/
    ├── Podfile
    ├── Reader.xcodeproj
    ├── Reader.xcworkspace  # pod install 后生成/更新
    ├── Reader/             # 主工程源码
    │   ├── Application/    # AppDelegate / SceneDelegate
    │   ├── Common/AI/      # 多厂商翻译客户端与配置
    │   ├── Common/LocalBook/
    │   ├── Common/Speech/
    │   ├── Database/       # WCDB 模型与 Manager
    │   ├── Sections/       # 书架 / 阅读 / 设置等
    │   └── Resource/       # Info.plist、资源、隐私清单
    └── Tests/AIHarness/    # AI / 备份相关本地测试
```

---

## 隐私与密钥

- **不要**把真实 API Key、备份 zip、个人书库数据库、模拟器截图提交进 Git。
- AI Key：Keychain 服务名 `reader.ios.ai.apikey`；备份中的 `ai_config` 仅元数据（`apiKey` 为空）。
- 本地调试目录 `.cursor/`、`.DS_Store`、根目录截图等已在 `.gitignore` 中忽略。
- 推送前建议自检：`git diff` / `git grep` 是否含 `sk-`、私钥、本机绝对路径等。

---

## 与上游的关系

本仓库基于阅小说 iOS 开源客户端演进，保留大量原工程结构与部分在线模块代码（发现 / 书库 / 搜索等可能仍在工程中，但默认产品路径为本地阅读）。

| 资源 | 链接 |
|------|------|
| 本仓库 | https://github.com/malu2335/reader-ios |
| 上游 iOS | https://github.com/yuenov/reader-ios |
| 上游 API 文档 | https://github.com/yuenov/reader-api |
| 上游 Android | https://github.com/yuenov/reader-android |

原「阅小说」产品与商店分发信息请以上游及官方渠道为准；本仓库为**独立维护的本地优先衍生版本**，应用展示名为 **轻阅**。

---

## 界面预览（历史截图）

以下图片来自原项目资源目录，仅供参考，与当前「轻阅」UI 可能不完全一致。

**iPhone**

<img src="resource/1.png" width="200"/><img src="resource/2.png" width="200"/><img src="resource/3.png" width="200"/><img src="resource/4.png" width="200"/>

**iPad**

<img src="resource/ipad1.png" width="200"/><img src="resource/ipad2.png" width="200"/><img src="resource/ipad3.png" width="200"/><img src="resource/ipad4.png" width="200"/>

---

## 声明

- 上游服务侧能力以阅小说开源说明为准；本客户端强调**本地文件阅读**与用户自备 AI 服务。
- 请勿将本项目用于侵犯著作权或其他违法行为；用户导入的内容与配置的 AI 密钥由用户自行负责。
- 软件按 MIT 许可提供，详见 [LICENSE](LICENSE)。
