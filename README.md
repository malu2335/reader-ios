# 纸羽轻阅（reader-ios）

纯本地运行的 iOS 阅读器。在 [阅小说开源 iOS 客户端](https://github.com/yuenov/reader-ios) 基础上，专注文件导入、阅读体验与离线备份；主界面仅保留 **书架 + 设置**，不连接在线书城、搜索、更新或 AI 服务。

| 项 | 说明 |
|----|------|
| 应用名 | **纸羽轻阅**（`CFBundleDisplayName`） |
| Bundle ID | `xyz.malu2335.reader` |
| 语言 | Objective-C |
| 最低系统 | iOS 15.0 |
| 依赖管理 | CocoaPods |
| 数据 | WCDB（SQLite）+ App 沙盒文件 |
| 仓库 | https://github.com/malu2335/reader-ios |

---

## 主要能力

### 本地阅读
- 导入 **TXT / EPUB / PDF / MOBI / ZIP / CBZ**，以及**包含图片的文件夹**（图集）
- ZIP/CBZ：按文件名自然序浏览图片（jpg/png/webp/gif 等）；文件夹会打包为 CBZ 再入库
- 章节解析与 WCDB 存储；`bookId < 0` 标识本地书，与在线链路隔离
- 内容哈希去重导入提示
- 阅读进度（含字符偏移）、**书签**；漫画用页码进度
- 正文净化规则、系统词典查询
- 书架长按菜单、类型化分享卡片

### 朗读与设置
- 系统 `AVSpeech` 朗读条；语音选择、收藏、个人声音导入指引
- 自定义字体导入
- 备份 / 恢复（布局参考 Legado：`bookshelf.json` / `config.json` / `books/`）

### 体验与工程
- UIScene 生命周期、启动页与书架预加载
- ProMotion / 高刷新相关路径
- 冷启动延后非关键初始化；设置页避免首点卡顿
- HTTP/HTTPS 请求在运行时统一拒绝，避免遗留模块或依赖意外外联

---

## 环境要求

- macOS + **Xcode**（建议较新版本；`Podfile` 含 Xcode 15+ / 新 clang 对 YYText、WCDB 的补丁）
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
    │   ├── Common/LocalBook/
    │   ├── Common/Speech/
    │   ├── Database/       # WCDB 模型与 Manager
    │   ├── Sections/       # 书架 / 阅读 / 设置等
    │   └── Resource/       # Info.plist、资源、隐私清单
```

---

## 隐私与数据

- App 不提供业务联网入口，并在 URL Loading 层拒绝 HTTP/HTTPS 请求。
- **不要**把备份 zip、个人书库数据库，以及含个人书库或隐私信息的调试截图提交进 Git；商店展示截图统一存放在 `AppStoreScreenshots/`。
- 本地调试目录 `.cursor/`、`.DS_Store`、根目录截图等已在 `.gitignore` 中忽略。
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

## 界面预览

以下截图来自当前「纸羽轻阅」版本，依次展示书架、正文阅读、阅读工具、排版设置、应用设置与正文净化。

<img src="AppStoreScreenshots/asc-1242x2688/01-bookshelf.png" width="180"/><img src="AppStoreScreenshots/asc-1242x2688/02-reading.png" width="180"/><img src="AppStoreScreenshots/asc-1242x2688/03-reading-tools.png" width="180"/>

<img src="AppStoreScreenshots/asc-1242x2688/04-typography.png" width="180"/><img src="AppStoreScreenshots/asc-1242x2688/05-settings.png" width="180"/><img src="AppStoreScreenshots/asc-1242x2688/06-reading-rules.png" width="180"/>

---

## 声明

- 本客户端仅处理用户主动导入的文件，不提供在线内容服务。
- 请勿将本项目用于侵犯著作权或其他违法行为；用户导入的内容由用户自行负责。
- 软件按 MIT 许可提供，详见 [LICENSE](LICENSE)。
