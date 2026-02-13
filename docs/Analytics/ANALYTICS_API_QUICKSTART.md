# Analytics API Quickstart

This quickstart shows how to call the analytics subsystem (based on the current code).
All examples below call the code as implemented in `lib/analytics`.

## Initialization (recommended sequence)

1. Pre-initialize (step 1/3) — call at app startup:

```dart
await AnalyticsManager.preInit();
```

2. After user agrees to privacy policy, grant privacy (step 2/3):

```dart
await AnalyticsManager.grant();
```

3. Final init (step 3/3):

```dart
await AnalyticsManager.init();
```

Notes:
- If `init()` has not completed, `AnalyticsManager.log()` will drop events and log a warning.
- `UmengAnalyticsService` performs actual work via native `MethodChannel('easyfile/analytics')`.
- `FirebaseAnalyticsService` is a no-op placeholder in the current codebase.

## Logging events

Use the helper wrappers in `AnalyticsHelper` for common events.
Examples:

```dart
// Scan lifecycle
await AnalyticsHelper.logScanStart('large_file');
await AnalyticsHelper.logScanFinish(scanType: 'large_file', durationMs: 5234, itemCount: 120, totalSizeMb: 1024.5);

// Clean actions
await AnalyticsHelper.logCleanAction(cleanType: 'large_file', itemCount: 5, sizeMb: 156.7);

// Privacy space
await AnalyticsHelper.logPrivacySpaceEnter('main_page');
await AnalyticsHelper.logPrivacySpaceAuth('password', true);

// Quick access
await AnalyticsHelper.logQuickAccessFolderClick(folderType: 'system', folderName: 'Downloads', isPinned: false);

// Home recommendation
await AnalyticsHelper.logHomeRecommendView('wechat', 21616);
```

## Verifying logs (Android)

Monitor native channel logs (Umeng native bridge):

```bash
adb logcat -s UmengAnalyticsChannel:D
```

You should see lines like:

```
D/UmengAnalyticsChannel: Logged event: scan_start with params: {type=large_file}
D/UmengAnalyticsChannel: Logged event: scan_finish with params: {type=large_file, duration_ms=5234, item_count=120, total_size_mb=1024.5}
```

If your build uses the `umeng` provider and native bridge is implemented, events will appear in the native logs.

## QA checklist

- Ensure `AnalyticsManager.preInit()` is called early in app startup.
- After granting privacy, call `AnalyticsManager.grant()` then `AnalyticsManager.init()`.
- Trigger a scan action and verify `scan_start` / `scan_finish` appear in logcat.
- If no native implementation exists, verify that calls fall back to Dart-side logging (no crash).

## Important implementation facts (code-based)

- Config file read by code: `config/analytics_config.yaml`.
- `AnalyticsHelper` contains the available event helper wrappers (38 methods as of current code).
- `AnalyticsManager` will drop events if `init()` has not completed.
- There is no runtime `enable`/`disable` API in `AnalyticsManager` in the current implementation.


---
Generated from code inspection on 2026-01-29.