# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

纸羽轻阅 (Paper Feather) — a strictly local-only iOS reader, forked from an online reader app. Objective-C, UIKit, CocoaPods, WCDB (SQLite). No account system, no server, no AI features. The app imports and reads user-supplied files only; it does not fetch anything from the network, and actively refuses to.

The project is mid-migration from an earlier "local-first but still has legacy online/AI code" state to this pure-local one (see `docs/plans/2026-07-17-paperfeather-offline-*.md` for the design/task breakdown, and `docs/project-status-2026-07-17.md` for what a prior review pass already fixed). Some directories described below as "dead" still exist on disk for history but are excluded from the Xcode target's Sources build phase, or neutered to fail immediately — don't assume a file's existence means it runs.

## Build, run, test

```bash
cd Reader
pod install                 # regenerates Reader.xcworkspace; required after any Podfile change
open Reader.xcworkspace     # always build the workspace, never Reader.xcodeproj directly
```

Command-line build (simulator, no signing needed — uses ad-hoc "Sign to Run Locally"):
```bash
xcodebuild -workspace Reader.xcworkspace -scheme Reader -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' build
```
Use a Release build (not just Debug) before treating a network/dependency change as verified — see `docs/plans/2026-07-17-paperfeather-offline-reader.md` Task 5.

Local test harnesses (no XCTest target exists; these are standalone Foundation executables compiled directly against shipped sources — see each script for the exact `clang` invocation):
```bash
bash Reader/Tests/AIHarness/run_tests.sh <scratch-dir>   # ZIP backup round-trip, replace-rule engine, local parsing
```
`AIHarness` predates the AI-removal work and still exercises `RDZipArchive`/backup logic even though its provider-request tests target code no longer compiled into the app — treat failures there as real regressions in the ZIP/backup path, not in AI behavior.

There is no CI, no Archive/export pipeline, and no XCUITest target. UI-interaction regressions (taps, gestures, page turns) cannot be verified headlessly — say so explicitly rather than claiming a UI fix works after only a build/install.

## Architecture

**Local book identity**: every imported book gets `bookId < 0`, derived by streaming-hashing the file (see `RDLocalBookManager`). Bookshelf queries, backup, and counters filter on `bookId < 0`; there is no positive-id (online) book path left to reach in the UI.

**Import/parse pipeline** (`Common/LocalBook/`): dedicated serial queue `com.reader.localbook.import` serializes import, delete, and PDF-cover-backfill against the same book so they can't race each other. Format parsers (`RDTxtBookParser`, `RDEpubBookParser`, `RDMobiBookParser`, PDF via `RDPdfReadController`/PDFKit, comics via `RDComicHelper`) are tolerant of malformed real-world files (e.g. EPUB falls back to regex extraction when NSXMLParser aborts on invalid XML) and enforce resource budgets against hostile/corrupt input (`RDZipArchive` caps entry count, per-entry and cumulative decompressed size, compression ratio, and verifies CRC32).

**Database** (`Database/`, WCDB): tables are `book`/`read`/`chapter`/`bookmark` in `Documents/book`; the `history` table is no longer written. **Read-record write rule**: the bookshelf list is a light projection (`getBookshelfDisplayList` omits `charpterModel`/`total`/`end`/etc.) — never `insertOrReplaceModel:` a partial model over an existing row, or you'll silently wipe reading progress. Use the narrow column-update APIs instead: `updateProgressWithModel:`, `updateTitle:author:forBookId:`, `updateCoverImg:forBookId:`, `asyncUpdatePage:forBookId:`. The `charpterModel` column on the read-record row stores a content-stripped chapter reference only; chapter text lives in the `chapter` table.

**Reading pipeline**: `RDReadPageViewController` → `RDReadController` → `RDReadParser` (CoreText pagination). Pagination is synchronous on whatever thread calls it — most call sites are on the main thread, and four of six are constrained by `UIPageViewControllerDataSource`'s synchronous-return contract, so a real async rewrite needs interactive test coverage first (see `docs/code-review-2026-07-17-systemic.md` P1-11). There's a hard 300k-character truncation guard against pathological single-chapter input.

**Network is blocked at three independent layers**, not just "not used":
1. No live UI entry point calls into the network layer.
2. `RDBaseApi` (`Service/Common/`) no longer talks to any HTTP client — `startWithCompletionBlock:` immediately completes with a local "offline version doesn't support network requests" error; it doesn't subclass `YTKRequest` anymore.
3. `AppDelegate` registers `RDOfflineURLProtocol`, an `NSURLProtocol` that intercepts and fails every `http`/`https` request regardless of which code path (including any future accidental one) issues it.

`Sections/Discover`, `Sections/Library`, `Sections/Search`, `Service/*`, and `Common/AI/` (AI translate client/config) are the legacy/removed-feature directories: unreachable from the two live tabs (`RDBookshelfController`, `RDSettingController`, wired in `RDMainController`), and the `Common/AI/` sources are excluded from the Xcode target's Sources build phase entirely. Don't "fix" bugs in these — if asked to work on them, confirm first whether the goal is restoring the feature or continuing the removal.

**Backup/restore** (`RDBackupManager`, legado-layout zip: `bookshelf.json`, `config.json`, `bookmarks.json`, `replace_rules.json`, `fonts/`, `books/`): restore sanitizes manifest-provided filenames to bare basenames and verifies the resolved path stays inside the app's books directory before writing (untrusted input). AI config is no longer written to or read from backups.

## Conventions

**Versioning** (`MARKETING_VERSION` in `Reader.xcodeproj/project.pbxproj`): patch bump for bug fixes/small changes, minor bump for new features, major bump for redesigns — bump according to what the current change actually is before committing.

**Design tokens**: paper-quiet color macros in `Common/Category/UIColor+rd_wid.h`, serif heading fonts in `Common/Category/UIFont+rd_wid.h` (STSongti-SC).

**CocoaPods on newer Xcode**: `Reader/Podfile`'s `post_install` patches WCDB (`std::list<const T>`) and YYText (a chained-comparison typo) for modern clang; these reapply automatically on `pod install`. If you edit files under `Reader/Pods/` directly for experimentation, `chmod u+w` first — they're not writable by default.
