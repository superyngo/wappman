# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.6] - 2026-02-24

### Fixed

- 修復 macOS sed -i 相容性問題，改用臨時檔案方式

## [1.0.5] - 2026-02-23

### Fixed

- 修復 macOS 上 `local -n`（nameref）不相容問題，改用 `eval` 實現，相容 bash 3.2+（macOS 內建版本）

## [1.0.4] - 2026-02-23

## [1.0.3]- 2026-02-11

### Added

- **RESTART_COMMAND**: 新增可在應用程式重啟前執行的自定義命令
  - 支援所有重啟場景（手動重啟、健康檢查重啟、文件變更重啟）
  - 可用於備份、通知、資源清理等操作
  - 執行失敗不影響重啟流程（僅記錄警告）
  - 支援 timeout 防止卡住

- **EVENT_INFO**: 統一的事件資訊環境變數機制
  - 所有 hook 命令（SUCCESS_CHECK_COMMAND、CRASH_COMMAND、RESTART_COMMAND）現在都可以存取事件上下文
  - 新增環境變數：
    - `WAPPMAN_EVENT_TIMESTAMP`: 事件時間戳
    - `WAPPMAN_EVENT_TIMESTAMP_UNIX`: Unix 時間戳
    - `WAPPMAN_EVENT_TYPE`: 事件類型（start, restart, success_check, crash）
    - `WAPPMAN_EVENT_TRIGGER`: 觸發原因（manual, health_check, file_change 等）
    - `WAPPMAN_SERVICE_NAME`: 服務名稱
    - `WAPPMAN_APP_EXEC`: 應用程式路徑
    - `WAPPMAN_STATE_DIR`: 狀態目錄
    - `WAPPMAN_MANAGER_LOG`: Manager 日誌路徑

### Changed

- SUCCESS_CHECK_COMMAND 現在接收觸發原因參數，提供更豐富的上下文資訊
- CRASH_COMMAND 除了原有的 `WAPPMAN_CRASH_REASON` 和 `WAPPMAN_CRASH_COUNT`，現在也包含完整的事件資訊

### Improved

- 更好的可觀測性：所有 hook 執行時都有完整的事件上下文
- 更靈活的自定義操作：可在重啟流程的不同階段執行自定義邏輯

## [1.0.2] - 2026-02-10

### Added

- Initial release of wappman
- Service lifecycle management (start, stop, restart)
- Health monitoring with configurable intervals
- File watching with inotify support
- Automatic crash recovery with retry limits
- Post-start validation commands
- Crash notification hooks
- Multi-service management
- Status reporting and uptime tracking
- Centralized logging with rotation
- XDG Base Directory specification compliance
- Configuration template generation
- Interactive service selection
- Comprehensive documentation (English and Traditional Chinese)

### Features in Detail

#### Core Service Management

- Start, stop, and restart services individually or all at once
- Process state tracking with PID management
- Graceful shutdown with configurable timeout
- Force kill fallback for stuck processes

#### Monitoring Capabilities

- Periodic health checks to ensure service availability
- File system watching for configuration changes
- Custom restart trigger files
- Automatic restart on file modifications

#### Crash Handling

- Configurable maximum restart attempts
- Success validation commands after startup
- Custom crash notification commands
- Detailed crash logging

#### Logging System

- Separate logs for manager and application
- Automatic log rotation based on retention days
- Real-time log viewing with tail -f
- Configurable log file locations

#### Configuration Management

- User-friendly configuration templates
- Per-service configuration files
- Environment variable support
- Relative and absolute path handling

#### State Management

- State persistence across restarts
- Lock file protection
- Uptime tracking
- Service status reporting

## [1.0.0] - 2026-02-09

### Added

- First stable release
- Complete feature set as described above
- English and Traditional Chinese documentation
- MIT License

[Unreleased]: https://github.com/superyngo/wappman/compare/v1.0.6...HEAD
[1.0.6]: https://github.com/superyngo/wappman/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/superyngo/wappman/compare/v1.0.4...v1.0.5
[1.0.3]: https://github.com/superyngo/wappman/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/superyngo/wappman/compare/v1.0.0...v1.0.2
[1.0.0]: https://github.com/superyngo/wappman/releases/tag/v1.0.0
