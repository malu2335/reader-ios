# Agent 须知 — reader-ios（纸羽轻阅）

> **强制**：动手改产品代码前，读本文件 + 本地 **`docs/handoff-2026-07-21.md`**（现状）。  
> 历史长文：`docs/handoff-2026-07-19.md`。  
> 用户要求：**所有操作按交接报告处理**，不得默认跳过版本号/分支/门禁。

## 每轮收尾 Checklist

1. 确认 **git 分支**（`master` vs `codex/jianyue-offline-reader`）。
2. **版本号**（见下）是否需要更新 → 更新 `project.pbxproj` + README。
3. **构建号** = `YYYYMMDDHHmm` 时间戳。
4. Xcode Cloud 钩子在 **`Reader/ci_scripts/ci_post_clone.sh`**（100755）。
5. master 产品修复若同步离线分支：合并后跑 **`Tests/OfflineOnlyHarness/run_tests.sh`**（禁止带回网络/AI）。
6. WCDB 事务内禁止批量 insert；独立 sqlite 必须 busy_timeout。
7. 业务弹窗用 **`RDPaperAlert`**，不要新加 LEEAlert / UIAlertController。

## 版本号（奇偶分产品线）

| 分支 | 第二位 | 功能变更 | 小修 |
|------|--------|----------|------|
| `master`（含 AI） | **奇数** | +2（…5→7→9） | 第三位 +1 |
| `codex/jianyue-offline-reader` | **偶数** | +2（…6→8） | 第三位 +1 |

例：master 当前 **1.13.0**；下次功能 → **1.15.0**；仅修 bug → **1.13.1**。两线独立演进。

## 模拟器

| 用途 | UDID |
|------|------|
| 手动 | `2F3087A4-7B4C-4F4A-8DAB-8E95F6F09E2D` |
| 单测 | `2D3EF1F5-3230-4CCE-A2C1-A2F8384A6B6D` |

勿在手动机上跑会 `resetLibrary` 的测试。优先 iOS 26.4 runtime。

## 文档

- `docs/` **gitignore**，换机需自备拷贝。
- 报告：`docs/code-review/`、`docs/plans/`；交接：`docs/handoff-*.md`。

## 历史雷区

- 1.3.4 / 1.3.5：导入死锁 / DB 队列堵死；1.5.0+ 才可用。
- 离线分支勿删 `p_currentReadController`（曾在翻译区段误删）。
