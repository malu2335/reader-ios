# 纸羽轻阅（reader-ios）

纯本地运行的 iOS 阅读器。在 [阅小说开源 iOS 客户端](https://github.com/yuenov/reader-ios) 基础上，专注文件导入、阅读体验与离线备份；主界面仅保留 **书架 + 设置**，不连接在线书城、搜索、更新或 AI 服务。

| 项 | 说明 |
|----|------|
| 应用名 | **纸羽轻阅**（`CFBundleDisplayName`） |
| Bundle ID | `xyz.malu2335.reader` |
| 语言 | Objective-C |
| 最低系统 | iOS 15.0 |
| 设备 | **仅 iPhone** |
| 依赖管理 | CocoaPods |
| 数据 | WCDB（SQLite）+ App 沙盒文件 |
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
| 字号 · 字体 · 翻页动画 | 导入 · 备份 · 隐私/开源入口 | legado 风格替换规则 |

| 隐私声明 | 开源软件使用声明 |
|:---:|:---:|
| <img src="Screenshots/07-privacy.png" width="180" alt="隐私声明"/> | <img src="Screenshots/08-opensource.png" width="180" alt="开源软件使用声明"/> |
| 设置内本地文档 · 无网络 | 完整许可与归属 · 可滚动复制 |

---

## 主要能力

### 本地阅读
- 导入 **TXT / EPUB / PDF / MOBI / ZIP / CBZ**，以及**包含图片的文件夹**（图集）
- 支持系统「用其他应用打开 / 分享」到纸羽轻阅（复制进沙盒，不修改源文件）
- ZIP/CBZ：按文件名自然序浏览图片（jpg/png/webp/gif 等）；文件夹会打包为 CBZ 再入库
- 章节解析与 WCDB 存储；`bookId < 0` 标识本地书
- 内容哈希去重导入提示
- 阅读进度（含字符偏移）、**书签**；漫画用页码进度
- 正文净化规则、系统词典查询
- 书架长按菜单、类型化分享卡片

### 朗读与设置
- 系统 `AVSpeech` 朗读条；语音选择、收藏、个人声音导入指引
- 自定义字体导入
- 备份 / 恢复（布局参考 Legado：`bookshelf.json` / `config.json` / `books/`）
- 设置内可查看 **隐私声明** 与 **开源软件使用声明**（本地文本，无网络）

### 体验与工程
- UIScene 生命周期、启动页与书架预加载
- ProMotion / 高刷新相关路径
- 冷启动延后非关键初始化；设置页避免首点卡顿
- HTTP/HTTPS 请求在运行时统一拒绝，避免遗留模块或依赖意外外联

---

## 环境要求

- macOS + **Xcode**（建议较新版本；`Podfile` 含 Xcode 15+ / 新 clang 对 YYText、WCDB 的补丁）
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
├── LICENSE                 # MIT（© 2020 阅小说；© 2026 Lu Ma / 纸羽轻阅）
├── Screenshots/            # README 界面预览（已压缩，可提交）
├── AppStoreScreenshots/    # 本地 ASC 全尺寸导出（默认 gitignore）
└── Reader/
    ├── Podfile
    ├── Reader.xcodeproj
    ├── Reader.xcworkspace  # pod install 后打开此 workspace
    ├── Tests/              # 静态 harness（配置 / 合规文稿等）
    └── Reader/             # 主工程源码
        ├── Application/    # AppDelegate / SceneDelegate
        ├── Common/LocalBook/
        ├── Common/Speech/
        ├── Database/       # WCDB 模型与 Manager
        ├── Sections/       # 书架 / 阅读 / 设置等
        └── Resource/       # Info.plist、隐私/开源声明、图标
```

---

## 隐私与数据

- App 不提供业务联网入口，并在 URL Loading 层拒绝 HTTP/HTTPS 请求。
- 设置页可查看随包发布的隐私声明与开源许可全文。
- **不要**把备份 zip、个人书库数据库，以及含个人书库或隐私信息的调试截图提交进 Git。
- 商店全尺寸截图建议放在本地 `AppStoreScreenshots/`；README 使用仓库内 `Screenshots/`。
- 本地调试目录 `.cursor/`、`.DS_Store`、`docs/`、`CLAUDE.md` 等已在 `.gitignore` 中忽略。
- 推送前建议自检：`git diff` / `git grep` 是否含 `sk-`、私钥、本机绝对路径等。

---

## 与上游的关系

本仓库基于阅小说 iOS 开源客户端演进。部分在线模块源码仅为历史追踪而保留，不进入产品入口；网络 API、AI 与网页实现不编译进 App，运行时还会统一拒绝 HTTP/HTTPS 请求。

| 资源 | 链接 |
|------|------|
| 本仓库 | https://github.com/malu2335/reader-ios |
| 上游 iOS | https://github.com/yuenov/reader-ios |
| 上游 API 文档 | https://github.com/yuenov/reader-api |
| 上游 Android | https://github.com/yuenov/reader-android |

原「阅小说」产品与商店分发信息请以上游及官方渠道为准；本仓库为**独立维护的纯本地衍生版本**，应用展示名为 **纸羽轻阅**。

---

## 声明

- 本客户端仅处理用户主动导入的文件，不提供在线内容服务。
- 请勿将本项目用于侵犯著作权或其他违法行为；用户导入的内容由用户自行负责。
- 软件按 MIT 许可提供，详见 [LICENSE](LICENSE)。本衍生版本保留上游「阅小说」版权声明，并增加 2026 年 Lu Ma（纸羽轻阅）版权行。
