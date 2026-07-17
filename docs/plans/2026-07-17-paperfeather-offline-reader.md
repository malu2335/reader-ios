# Paper Feather Offline Reader Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 iOS 工程改造成名为“纸羽轻阅”的纯本地阅读器，移除所有可达的外部联网功能并阻止 HTTP(S) 外联。

**Architecture:** 从 UI、业务数据、传输层和构建依赖四层收敛。删除在线与 AI 入口，只读取本地书；将旧 API 改为离线失败；注册全局 HTTP(S) 拦截器；移除联网 Pod 和 AI/网页 Sources。

**Tech Stack:** Objective-C、UIKit、WCDB、CocoaPods、Xcode build settings、NSURLProtocol

---

### Task 1: 品牌改名

**Files:**
- Modify: `Reader/Reader/Resource/Info.plist`
- Modify: `Reader/Reader/Resource/Base.lproj/LaunchScreen.storyboard`
- Modify: `Reader/Reader/Common/Controller/RDSplashViewController.m`
- Modify: `Reader/Reader/Sections/Bookshelf/Cell/RDBookshelfCell.m`
- Modify: `Reader/Reader.xcodeproj/project.pbxproj`
- Modify: `README.md`

**Step 1:** 把展示名、产品名、启动页与分享标签统一为“纸羽轻阅”。

**Step 2:** 调整启动品牌容器宽度，确保四字名称不截断。

**Step 3:** 运行 `rg '轻阅|简阅'`，确认仅保留必要的迁移说明。

### Task 2: 移除可达 AI 与在线入口

**Files:**
- Modify: `Reader/Reader/Sections/Setting/RDSettingController.m`
- Modify: `Reader/Reader/Common/Manager/RDBookshelfPrefetch.m`
- Modify: `Reader/Reader/Sections/Bookshelf/Read/View/RDReadTopBar.h`
- Modify: `Reader/Reader/Sections/Bookshelf/Read/View/RDReadTopBar.m`
- Modify: `Reader/Reader/Sections/Bookshelf/Read/View/RDMenuView.m`
- Modify: `Reader/Reader/Sections/Bookshelf/Read/RDReadPageViewController.m`
- Modify: `Reader/Reader/Sections/Bookshelf/Read/RDReadController.h`
- Modify: `Reader/Reader/Sections/Bookshelf/Read/RDReadController.m`

**Step 1:** 删除设置中的 AI 行、配置读取和备份文案。

**Step 2:** 删除阅读顶栏翻译按钮、委托和后台翻译状态机。

**Step 3:** 编译检查所有 `translateAction` / `RDAI` 引用已从可达代码消失。

### Task 3: 将数据与备份限定为本地内容

**Files:**
- Modify: `Reader/Reader/Database/RDReadRecordManager.mm`
- Modify: `Reader/Reader/Common/LocalBook/RDBackupManager.h`
- Modify: `Reader/Reader/Common/LocalBook/RDBackupManager.m`
- Modify: `Reader/Reader/Sections/Bookshelf/Cell/RDBookshelfCell.m`

**Step 1:** 书架列表、计数和备份查询增加 `bookId < 0` 条件。

**Step 2:** 删除在线封面下载分支。

**Step 3:** 备份停止写入/恢复 AI 配置，但继续兼容旧 zip 的其他条目。

### Task 4: 阻断网络传输并收缩依赖

**Files:**
- Modify: `Reader/Reader/Application/AppDelegate.m`
- Modify: `Reader/Reader/Service/Common/RDBaseApi.h`
- Modify: `Reader/Reader/Service/Common/RDBaseApi.m`
- Modify: `Reader/Reader/Model/Common/RDGlobalModel.m`
- Modify: `Reader/Reader/Util/RDUtilities.m`
- Modify: `Reader/Reader/Resource/Info.plist`
- Modify: `Reader/Podfile`
- Modify: `Reader/Podfile.lock`
- Modify: `Reader/Reader.xcodeproj/project.pbxproj`

**Step 1:** 注册拒绝 HTTP/HTTPS 的 `NSURLProtocol`，并为旧 API 提供本地离线失败实现。

**Step 2:** 移除真实服务域名与远程封面 URL 拼接。

**Step 3:** 从 Podfile 删除 YTKNetwork 与 NJKWebViewProgress，执行 `pod install` 更新锁文件。

**Step 4:** 从 Sources 移除 AI client/config/controller、翻译 helper 和网页 controller/view。

### Task 5: 验证纯本地约束

**Files:**
- Test: `Reader/Tests/AIHarness/run_tests.sh`
- Verify: `Reader/Reader.xcodeproj/project.pbxproj`
- Verify: `Reader/Podfile.lock`

**Step 1:** 运行可继续适用的本地解析与备份测试。

**Step 2:** 以独立 DerivedData 执行 Release 构建。

**Step 3:** 扫描 App Sources、Pods 与构建设置，确认无 YTKNetwork/AFNetworking、AI Sources、ATS 网络例外和可达 HTTP(S) 调用。

**Step 4:** 检查 git diff，确保原有书架并发修复未被覆盖。

