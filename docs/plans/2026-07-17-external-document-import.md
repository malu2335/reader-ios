# 外部应用分享文档导入 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让用户在“文件”、邮件、网盘、聊天工具等外部应用分享 `epub`、`mobi`、`azw`、`zip`、`cbz`、`pdf`、`txt` 文件时，可以在系统分享菜单中选择“纸羽轻阅”，并把文件安全地复制到本 App 的书架中。

**Architecture:** 不新增 Share Extension，也不接入网络。使用 iOS 原生文档类型声明让 App 成为这些文件的“打开方式”，继续复用现有 `RDLocalBookManager` 导入、去重、解析和安全作用域访问链路。补强 Scene 冷启动文件接收，确保文件在启动页预加载完成后只导入一次；旧版 AppDelegate 回调保留为兼容路径。

**Tech Stack:** Objective-C、UIKit Scene 生命周期、Uniform Type Identifiers、`CFBundleDocumentTypes`、`UTImportedTypeDeclarations`、现有 `RDLocalBookManager`、Xcode/iOS Simulator。

---

## 已确认的项目现状

- 当前工作分支：`codex/jianyue-offline-reader`。
- 支持扩展名已经由 `RDLocalBookManager.supportedExtensions` 定义为：`txt`、`epub`、`mobi`、`pdf`、`azw`、`zip`、`cbz`。
- `RDLocalBookManager.importBookAtURL:complete:` 已具备安全作用域访问、复制到 App 沙盒、文件哈希去重和格式解析能力，不需要另写一套导入器。
- `SceneDelegate` 已实现运行中接收 `scene:openURLContexts:`；`AppDelegate` 也保留了旧生命周期的 `application:openURL:options:`。
- `Info.plist` 已声明 TXT、EPUB、PDF、MOBI/AZW、ZIP、CBZ 文档类型，但缺少 `LSSupportsOpeningDocumentsInPlace`，这也是此前上传构建时 App Store Connect 警告 90737 的原因。
- 当前冷启动通过一次性通知等待书架预加载。若通知在观察者注册前已经发出，存在文件未导入的竞态。
- App 自身导入后保存副本，不应该原地修改文件提供方中的源文件，因此 `LSSupportsOpeningDocumentsInPlace` 应设为 `false`。

## 非目标

- 不新增网络能力，不从 URL 下载书籍。
- 不新增 Share Extension；本需求针对外部应用分享出来的文件文档，系统“打开方式”注册足够覆盖。
- 不把 `public.data` 作为可打开的通配文档类型，避免 App 对大量无关文件出现在分享菜单中。
- 不修改现有书籍解析、阅读、备份格式。
- 本计划执行阶段不自动上传 App Store Connect；上传应在模拟器和 Release 构建通过后由单独指令触发，并递增构建号。

## Task 1：为文档类型配置增加可重复验证

**Files:**

- Create: `Reader/Tests/ExternalImportHarness/run_tests.sh`
- Test: `Reader/Reader/Resource/Info.plist`

**Step 1: 编写失败的配置测试**

脚本使用 `/usr/libexec/PlistBuddy` 或 `plutil` 读取 plist，并逐项断言：

- `LSSupportsOpeningDocumentsInPlace` 存在且为 `false`。
- `CFBundleDocumentTypes` 覆盖以下 UTI：
  - `public.plain-text`
  - `org.idpf.epub-container`
  - `com.adobe.pdf`
  - `xyz.malu2335.reader.mobi`
  - `public.zip-archive`
  - `xyz.malu2335.reader.cbz`
- MOBI 自定义 UTI 覆盖扩展名 `mobi`、`azw`。
- CBZ 自定义 UTI 覆盖扩展名 `cbz`。
- MOBI、CBZ 的自定义 UTI 均符合 `public.data` 与 `public.content`。

脚本失败时应明确打印缺少的键或类型；成功时打印 `External import plist checks passed.`。

**Step 2: 运行测试并确认当前失败**

Run:

```bash
bash Reader/Tests/ExternalImportHarness/run_tests.sh
```

Expected: 因缺少 `LSSupportsOpeningDocumentsInPlace` 和自定义类型的 `public.content` 约束而失败。

## Task 2：注册系统分享菜单中的受支持文件类型

**Files:**

- Modify: `Reader/Reader/Resource/Info.plist`
- Test: `Reader/Tests/ExternalImportHarness/run_tests.sh`

**Step 1: 声明导入副本语义**

在顶层加入：

```xml
<key>LSSupportsOpeningDocumentsInPlace</key>
<false/>
```

此配置与现有行为一致：收到外部文件后复制进 App 的 LocalBooks 目录，不编辑来源文件。

**Step 2: 补强 MOBI/AZW 导入类型**

保留自定义 UTI `xyz.malu2335.reader.mobi`，确保：

```xml
<key>UTTypeConformsTo</key>
<array>
    <string>public.data</string>
    <string>public.content</string>
</array>
```

扩展名继续包含 `mobi`、`azw`。在 `UTTypeTagSpecification` 中补充 MIME：

```xml
<key>public.mime-type</key>
<array>
    <string>application/x-mobipocket-ebook</string>
    <string>application/vnd.amazon.ebook</string>
</array>
```

**Step 3: 补强 CBZ 导入类型**

保留 `xyz.malu2335.reader.cbz`，使其符合：

```xml
<array>
    <string>public.zip-archive</string>
    <string>public.data</string>
    <string>public.content</string>
</array>
```

继续保留扩展名 `cbz` 和现有 MIME `application/vnd.comicbook+zip`、`application/x-cbz`。

**Step 4: 不重复声明系统已有类型**

EPUB、PDF、TXT、ZIP 继续仅出现在 `CFBundleDocumentTypes` 中，不在 `UTImportedTypeDeclarations` 中重新定义。自定义导入声明只用于系统未标准定义的 MOBI/AZW 与 CBZ。

**Step 5: 运行配置测试**

Run:

```bash
bash Reader/Tests/ExternalImportHarness/run_tests.sh
plutil -lint Reader/Reader/Resource/Info.plist
```

Expected: 两条命令均成功。

## Task 3：修复冷启动分享文件的接收竞态

**Files:**

- Modify: `Reader/Reader/Application/SceneDelegate.m`

**Step 1: 保存待导入的冷启动 URL Contexts**

在 `SceneDelegate.m` 的类扩展中增加：

```objc
@interface SceneDelegate ()
@property (nonatomic, copy) NSSet<UIOpenURLContext *> *pendingOpenURLContexts;
@end
```

在 `willConnectToSession` 中直接复制 `connectionOptions.URLContexts` 到该属性，不再注册一次性预加载完成通知。

**Step 2: 主界面开始呈现后消费一次待导入文件**

在 `splash.onFinished` 中先调用 `p_presentMainWithAppDelegate:`，随后调用新的私有方法：

```objc
- (void)p_importPendingURLsForScene:(UIScene *)scene
{
    NSSet<UIOpenURLContext *> *contexts = self.pendingOpenURLContexts;
    self.pendingOpenURLContexts = nil;
    if (contexts.count > 0) {
        [self scene:scene openURLContexts:contexts];
    }
}
```

这样冷启动文件会在书架预加载完成、主界面开始切换后导入，且属性清空保证每批 URL 只消费一次。

**Step 3: 保留运行中打开文件路径**

继续使用已有的：

```objc
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
```

逐个过滤 `fileURL` 和 `isSupportedFileURL:`，然后调用 `importBookAtURL:complete:`。不接受 HTTP/HTTPS URL。

## Task 4：统一旧生命周期兼容回调的书架刷新行为

**Files:**

- Modify: `Reader/Reader/Application/AppDelegate.m`

**Step 1: 引入书架预取刷新器**

增加：

```objc
#import "RDBookshelfPrefetch.h"
```

**Step 2: 导入完成后刷新书架缓存**

在 `application:openURL:options:` 的导入 completion 开头调用：

```objc
[RDBookshelfPrefetch refreshAsync:nil];
```

使旧回调路径与 SceneDelegate 行为一致，避免文件已入库但书架暂时不显示。

## Task 5：静态检查和构建验证

**Files:**

- Verify: `Reader/Reader/Resource/Info.plist`
- Verify: `Reader/Reader/Application/SceneDelegate.m`
- Verify: `Reader/Reader/Application/AppDelegate.m`

**Step 1: 运行测试与检查差异**

Run:

```bash
bash Reader/Tests/ExternalImportHarness/run_tests.sh
git diff --check
git diff -- Reader/Reader/Resource/Info.plist Reader/Reader/Application/SceneDelegate.m Reader/Reader/Application/AppDelegate.m Reader/Tests/ExternalImportHarness/run_tests.sh
```

Expected: 测试通过，无空白错误；差异只包含本计划要求的内容。

**Step 2: Debug 模拟器构建**

Run:

```bash
cd Reader
xcodebuild -workspace Reader.xcworkspace -scheme Reader -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Expected: `BUILD SUCCEEDED`。

**Step 3: Release 模拟器构建**

Run:

```bash
cd Reader
xcodebuild -workspace Reader.xcworkspace -scheme Reader -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Expected: `BUILD SUCCEEDED`。纯本地/网络封锁相关项目必须以 Release 构建也成功作为完成条件。

## Task 6：模拟器端到端验收

**Files:**

- Create temporarily outside repository: EPUB、MOBI、ZIP、CBZ 测试文件
- Verify: installed simulator app

**Step 1: 安装干净构建**

在当前可用 iPhone 模拟器启动并安装新构建。若已有旧数据，优先保留；只在测试夹具重复导致无法判断时删除该测试书籍，不清空用户项目数据。

**Step 2: 验证运行中导入**

分别从“文件”或测试宿主 App 分享有效的 EPUB、MOBI、ZIP、CBZ 文件，确认：

- 分享菜单中出现“纸羽轻阅”。
- 选择后跳转 App。
- 成功提示为“《书名》已加入书架”。
- 书架无需重启即可出现新书。
- EPUB/MOBI 可进入正文阅读；ZIP/CBZ 作为漫画可打开图片页。

**Step 3: 验证冷启动导入**

彻底终止 App 后，从外部应用再次分享一个未导入文件，确认启动页结束后文件只加入一次且书架可见。

**Step 4: 验证异常和边界**

- 再次分享相同文件，提示已经在书架，不产生重复记录。
- 分享不支持的扩展名，App 不应作为打开方式出现；即使系统回调到 App 也应拒绝。
- 分享损坏的 ZIP/EPUB/MOBI，显示现有解析错误，不崩溃。
- 原始外部文件不被修改或删除。

**Step 5: 记录限制**

当前项目没有 XCUITest target，因此“是否出现在第三方 App 分享菜单中”必须通过模拟器 UI 人工确认；仅构建成功或 `simctl openurl` 不能替代这一项。

## Task 7：在设置中加入隐私声明与开源软件使用声明

**Files:**

- Create: `Reader/Reader/Sections/Setting/RDLegalDocumentController.h`
- Create: `Reader/Reader/Sections/Setting/RDLegalDocumentController.m`
- Create: `Reader/Reader/Resource/PrivacyPolicy.zh-Hans.txt`
- Create: `Reader/Reader/Resource/OpenSourceLicenses.txt`
- Modify: `Reader/Reader/Sections/Setting/RDSettingController.m`
- Modify: `Reader/Reader.xcodeproj/project.pbxproj`
- Verify: `Reader/Reader/Resource/PrivacyInfo.xcprivacy`
- Create: `Reader/Tests/LegalDocumentsHarness/run_tests.sh`

**Step 1: 编写隐私声明正文**

为“纸羽轻阅”编写简体中文隐私声明，使用本地文本资源随 App 一起发布。正文至少包含：

- 生效日期、版本号、App 名称和开发者/联系邮箱；联系信息未确认前必须保留显眼占位符，不能虚构。
- 产品定位：用户自行导入并阅读 TXT、EPUB、MOBI、AZW、PDF、ZIP、CBZ 等文件。
- 本地数据：导入书籍、封面、阅读进度、书签、阅读设置、字体、替换规则、语音偏好和备份内容保存在设备或用户主动选择的备份位置。
- 数据收集：当前无账号、广告、分析、追踪和开发者服务器；以最终 Release Target 和依赖审计为准，不能只凭产品描述下结论。
- 权限与系统能力：用户主动选择文件、系统词典、系统朗读/个人声音、系统分享面板等能力由 iOS 提供；说明触发方式和用途。
- 数据分享：只有用户主动导出备份、分享摘录或调用系统分享面板时，数据才交给用户选择的目标应用；开发者不应声称能够控制目标应用的处理方式。
- 数据保留和删除：书籍可从书架删除，可使用“清空书架”，卸载 App 会删除 App 沙盒数据；用户另存到“文件”或其他位置的备份需由用户自行删除。
- 安全说明：App 不上传阅读内容，但设备、外部备份位置和接收分享的第三方应用仍需由用户妥善保护。
- 儿童隐私、声明变更和联系方式。

隐私声明必须与 `PrivacyInfo.xcprivacy`、App Store Connect“App 隐私”问卷和最终二进制的实际行为保持一致。现有 manifest 声明 `NSPrivacyTracking = false`、`NSPrivacyCollectedDataTypes` 为空，并列出 UserDefaults/FileTimestamp 的 Required Reason API；实现前需要重新核对依赖生成的 Privacy Report。

**Step 2: 编写开源软件使用声明**

`OpenSourceLicenses.txt` 需要包含：

- 本项目源自 MIT License 项目“阅小说”，保留根目录 `LICENSE` 中的原始版权和完整 MIT 许可文本。
- 当前 `Podfile.lock` 中实际进入 App 的直接和传递依赖名称、版本、版权信息及完整许可文本。
- 当前已识别依赖包括：FDFullscreenPopGesture、GBDeviceInfo、JLRoutes、KVOController、libwebp、Masonry、MBProgressHUD、MGSwipeTableCell、MJRefresh、RDVTabBarController、SDWebImage、SDWebImageWebPCoder、SQLiteRepairKit、UITextView+Placeholder、WCDB、WCDBOptimizedSQLCipher、WMPageController、YYModel、YYText。
- 不仅列出软件名称或许可证简称；需要从当前锁定版本的 `Reader/Pods/**/LICENSE`、`COPYING`、podspec 和必要的 NOTICE 文件复制完整、准确的归属与许可内容。
- 审计手工加入 Target 的第三方源码、字体、图标和其他资源，不能只覆盖 CocoaPods。
- 合并重复许可证正文时仍需保留每个组件对应的版权归属和许可映射。

生成声明后，应把它当作发布制品审查；依赖版本变化时同步更新，避免声明与二进制不一致。

**Step 3: 增加本地法律文档页面**

实现通用 `RDLegalDocumentController`：

- 初始化参数包含页面标题和 bundle 文本资源名。
- 使用只读 `UITextView` 展示 UTF-8 文本，不使用 WebView、不请求远程 URL。
- 支持动态字体、Safe Area、内容滚动和系统“选择/复制”。
- 视觉使用现有 `RDBackgroudColor`、`RDSurfaceColor`、字体与 `RDTopView` 风格。
- 文本资源缺失或读取失败时显示明确错误，不能呈现空白页面。
- 页面不需要“同意”按钮；它们是可随时查看的声明，不应伪装成首次启动强制授权。

**Step 4: 在设置页“关于”分组增加入口**

在 `RDSettingRow` 增加：

```objc
RDSettingRowPrivacy,
RDSettingRowOpenSource,
```

设置页最后一个“关于”分组按以下顺序显示：

1. 隐私声明
2. 开源软件使用声明
3. 版本

前两行使用 disclosure indicator，点击后分别进入本地隐私声明和开源声明页面；版本行继续只读。

**Step 5: 将源文件和文本加入正确 Target**

更新 `project.pbxproj`：

- `RDLegalDocumentController.m` 加入 Reader Target 的 Sources。
- 两个 `.txt` 文件加入 Reader Target 的 Copy Bundle Resources。
- 避免重复资源、错误 Target membership 或把 `Pods` 整目录复制进 App。

**Step 6: 增加静态测试**

`LegalDocumentsHarness/run_tests.sh` 至少验证：

- 两个文本文件存在、非空且为 UTF-8。
- 隐私声明包含生效日期、数据收集、设备本地存储、分享/披露、删除方式、联系方式和变更说明。
- 开源声明覆盖 `Podfile.lock` 当前所有组件，并包含根项目 MIT 版权声明。
- 两个文本文件存在于 Xcode Resources 构建阶段。
- 设置页存在两个可点击行，并指向正确资源。
- `PrivacyInfo.xcprivacy` 能通过 `plutil -lint`。

Run:

```bash
bash Reader/Tests/LegalDocumentsHarness/run_tests.sh
```

Expected: 所有声明内容与资源接线检查通过。

**Step 7: 模拟器人工验收**

- 设置 → 隐私声明可以打开、滚动、复制，返回正常。
- 设置 → 开源软件使用声明可以打开并流畅滚动长文本。
- 大字体辅助功能下标题和正文不截断。
- 飞行模式下两个页面仍能完整打开。
- Release 构建的 App Bundle 内包含两个文档，且内容与仓库一致。

**Step 8: 补齐 App Store Connect 元数据**

App 内隐私声明不能替代 App Store Connect 的 Privacy Policy URL。提交审核前还需要提供一个无需登录、长期可访问且内容与 App 内声明一致的公开隐私政策 URL，并重新核对 App Store Connect“App 隐私”回答。Apple 审核指南要求隐私政策在 App Store Connect 元数据和 App 内都易于访问。

**Apple 官方参考：**

- [App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

隐私声明属于合规文稿。最终发布文本应由开发者核实主体名称、联系方式、实际数据行为及适用法律；本计划不替代法律意见。

## Task 8：分析 App 加密文稿与出口合规选项

**Files:**

- Inspect: `Reader/Reader/**/*.m`
- Inspect: `Reader/Reader/**/*.h`
- Inspect: `Reader/Podfile`
- Inspect: `Reader/Podfile.lock`
- Inspect: Release Archive 中实际链接的 frameworks/libraries
- Potentially Modify: `Reader/Reader/Resource/Info.plist`

App Store Connect 后续需要回答：**“你的 App 采用了哪种类型的加密算法？”**，可选项为：

1. 专有或未被国际标准主体（IEEE、IETF、ITU 等）视为标准的加密算法。
2. 代替在 Apple 操作系统中使用或访问加密，或与这些操作同时使用的标准加密算法。
3. 兼用上述两种算法。
4. 不属于上述的任意一种算法。

此项不能仅凭 App“没有联网”直接判断。执行上传前应针对最终 Release 构建完成以下分析，再在 App Store Connect 中选择。

**Step 1: 审计 App Target 的实际加密调用**

搜索并逐项确认最终 App Target 内是否实际调用：

- CryptoKit、CommonCrypto、Security/Keychain 加密接口。
- OpenSSL、BoringSSL、libsodium、NaCl 或其他加密库。
- AES、DES、3DES、RSA、ECC、ChaCha、Blowfish 等加密算法。
- 自研或非国际标准加密/解密实现。
- 带密码或加密功能的 ZIP/电子书处理代码。
- TLS、VPN、加密通信、端到端加密或自定义安全协议。

只检查实际编入当前 Target 且运行可达的代码；仓库中已排除 Target 的遗留网络/AI 文件不能单凭文件存在就算作 App 使用了加密。

**Step 2: 审计 CocoaPods 和最终链接产物**

检查 `Podfile.lock`、Build Phases、Link Binary With Libraries 和 Release Archive，确认第三方依赖是否携带并实际使用加密能力。依赖内部存在加密代码但未链接或不可达时应记录证据；实际链接并使用时必须纳入判断。

**Step 3: 区分加密与非加密处理**

以下能力本身通常不能直接等同于 App 使用加密算法，但仍需记录实现：

- 用于书籍去重的 MD5/SHA 等单向摘要或文件哈希。
- CRC32 完整性校验。
- Base64、字符编码和压缩/解压缩。
- 未设置密码的普通 ZIP/CBZ 归档。
- Apple 操作系统自动提供的文件保护、代码签名等平台能力。

**Step 4: 形成可追溯结论**

在上传前补充一份简短审计记录，至少包含：

- 搜索过的关键字和目录。
- App Target 实际链接的相关库。
- 每个疑似加密用途是否可达、用途是什么。
- 最终选择上述哪一项，以及选择理由。
- 是否属于美国出口合规豁免；若判断存在不确定性，先由熟悉出口合规的专业人士确认，不在 App Store Connect 中猜选。

**Step 5: 当前待验证的初步判断**

根据项目目前“纯本地阅读器、网络请求被阻断、主要进行文件解析和哈希去重”的结构，初步候选是第 4 项“**不属于上述的任意一种算法**”。这只是待审计假设，不是最终合规结论；尤其需要确认 ZIP 组件、电子书解析器、依赖库和 Release 二进制没有实际使用标准或专有加密。

**Step 6: 审计通过后决定是否声明 plist 键**

如果最终确认 App 不使用需要申报的非豁免加密，再评估在 `Info.plist` 中加入：

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

该键只能在审计结论支持时添加。添加后重新 Archive，并确认上传处理结果与 App Store Connect 的加密文稿回答一致。

**Apple 官方参考：**

- [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
- [`ITSAppUsesNonExemptEncryption`](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- [Determine and upload app encryption documentation](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)

## Task 9：版本与交付（仅在用户明确要求上传时执行）

**Files:**

- Modify: `Reader/Reader.xcodeproj/project.pbxproj`

**Step 1: 递增版本**

这是新增外部导入入口，按仓库约定更新 `MARKETING_VERSION`；上传 App Store Connect 前递增 `CURRENT_PROJECT_VERSION`，不能复用已上传的 `1.2.2 (10202)`。

**Step 2: Archive 前最终检查**

Run:

```bash
git status --short
bash Reader/Tests/ExternalImportHarness/run_tests.sh
```

确认没有把测试文档、构建产物、临时凭据或无关修改加入提交。

**Step 3: Archive、Validate、Upload**

先完成 Task 7 的隐私/开源声明和 Task 8 的加密文稿分析，再使用当前 App Store 签名配置生成 Archive，先 Validate，再 Upload。上传成功后在 App Store Connect/TestFlight 确认新构建完成处理，并确认不再出现 90737 文档配置警告。

## 完成标准

- 外部应用分享 EPUB、MOBI、AZW、ZIP、CBZ、PDF、TXT 时，系统可选择“纸羽轻阅”。
- 冷启动和运行中均能导入，导入完成后书架及时刷新。
- 重复文件不重复入库，损坏或不支持文件不会导致崩溃。
- App 只复制并读取外部文件，不修改源文件、不恢复网络功能。
- plist 配置测试、Debug 构建、Release 构建全部通过。
- 模拟器人工验证分享菜单与核心格式导入通过。
- 设置页可在无网络状态完整查看隐私声明和开源软件使用声明，内容与最终 Release 构建及 App Store Connect 隐私回答一致。
- 已完成最终 Release 构建的加密能力审计，并为 App Store Connect 加密文稿选项保留明确依据。
