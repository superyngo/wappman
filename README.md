# wappman

[English](#english) | [繁體中文](#繁體中文)

---

## English

### Overview

**wappman** is a user-level service manager for Linux/Unix systems. It manages multiple service lifecycles (start/stop/restart) with optional health checking (periodic process monitoring) and file watching (auto-restart on file changes). Pure Bash script solution with no external dependencies except for file watching features.

### Features

- 🚀 **Service Lifecycle Management** - Start, stop, restart services with ease
- 🔍 **Health Monitoring** - Periodic process health checking with configurable intervals
- 👁️ **File Watching** - Auto-restart services when configuration files change
- 📊 **Status Reporting** - Real-time service status and uptime information
- 📝 **Logging** - Centralized logging with automatic log rotation
- 🔄 **Crash Recovery** - Automatic restart on crashes with configurable retry limits
- 🎯 **Post-Start Validation** - Optional health check commands after service start
- 🔔 **Crash Notifications** - Execute custom commands when service crashes
- 📦 **Multi-Service Support** - Manage multiple services simultaneously

### Requirements

- **Bash** 4.0+
- **inotify-tools** (only required if file watching is enabled)

#### Installing Dependencies

**Debian/Ubuntu:**

```bash
sudo apt install inotify-tools
```

**RHEL/CentOS/Fedora:**

```bash
sudo yum install inotify-tools
```

**Arch Linux:**

```bash
sudo pacman -S inotify-tools
```

### Installation

#### Method 1: Wenget

```bash
wenget install wappman
```

#### Method 2: Clone Repository

```bash
git clone https://github.com/superyngo/wappman.git
cd wappman
chmod +x wappman
```

#### Method 3: Download Release

Download the latest release from the [Releases](https://github.com/superyngo/wappman/releases) page and extract it:

```bash
tar -xzf wappman-v*.tar.gz
cd wappman
chmod +x wappman
```

#### Optional: Add to PATH

```bash
# Create a symlink in your local bin directory
mkdir -p ~/.local/bin
ln -s "$(pwd)/wappman" ~/.local/bin/wappman

# Make sure ~/.local/bin is in your PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Quick Start

1. **Create a service configuration:**

```bash
./wappman config myapp
```

This opens a configuration template. Edit the `APP_EXEC` field to point to your application:

```bash
APP_EXEC="/path/to/your/application"
APP_ARGS="--port 8080"
```

2. **Start the service:**

```bash
./wappman start myapp
```

3. **Check service status:**

```bash
./wappman status myapp
```

4. **View logs:**

```bash
./wappman log myapp
```

### Usage

```bash
./wappman <command> [SERVICE_NAME|all]
```

#### Available Commands

| Command                       | Description                                  |
| ----------------------------- | -------------------------------------------- |
| `list`                        | List all configured services                 |
| `config <name>`               | Create or edit service configuration         |
| `start <name\|all>`           | Start service(s)                             |
| `stop <name\|all>`            | Stop service(s)                              |
| `restart <name\|all>`         | Restart service(s)                           |
| `restart-app <name\|all>`     | Restart only the application (keep monitors) |
| `restart-monitor <name\|all>` | Restart only monitors (health/watcher)       |
| `status <name\|all>`          | Show service status                          |
| `log <name>`                  | View service logs (tail -f)                  |
| `log-rotate <name\|all>`      | Rotate and clean old logs                    |
| `clean <name\|all>`           | Clean state files                            |
| `del <name>`                  | Delete service configuration                 |

### Configuration Options

Service configurations are stored in `~/.config/wappman/<SERVICE_NAME>.conf`. Here are the main configuration options:

#### Basic Settings

- `APP_EXEC` - **Required**. Path to your application executable
- `APP_ARGS` - Optional command-line arguments for your application
- `STATE_DIR` - Directory for state files (PID, locks, etc.)
- `MANAGER_LOG_FILE` - Path to wappman's log file
- `APP_LOG_FILE` - Path to application's log file (leave empty to merge with manager log)

#### Health Check Settings

- `HEALTH_CHECK_INTERVAL` - Health check interval in seconds (0 to disable)

#### File Watching Settings

- `WATCH_FILES` - Space-separated list of files to watch for changes
- `RESTART_FILE` - Special file that triggers restart when modified

#### Restart and Timeout Settings

- `RESTART_DELAY` - Delay before restart (seconds)
- `RESTART_MIN_INTERVAL` - Minimum interval between restarts (seconds)
- `STOP_TIMEOUT` - Timeout for graceful stop before force kill (seconds)

#### Crash Recovery Settings

- `SUCCESS_CHECK_COMMAND` - Command to validate successful start (e.g., `curl -f http://localhost:8080/health`)
- `SUCCESS_CHECK_DELAY` - Delay before running success check (seconds)
- `CRASH_RESTART_MAX` - Maximum restart attempts (0 for unlimited)
- `CRASH_COMMAND` - Command to execute when service crashes

#### Log Rotation

- `LOG_RETAIN_DAYS` - Number of days to retain logs (default: 7)

### Example Configuration

```bash
# myapp.conf
APP_EXEC="/usr/local/bin/myapp"
APP_ARGS="--port 8080 --config /etc/myapp/config.yaml"

# Enable health checks every 20 minutes
HEALTH_CHECK_INTERVAL=1200

# Watch config file for changes
WATCH_FILES="/etc/myapp/config.yaml"

# Wait 10 seconds after restart
RESTART_DELAY=10

# Validate service is responding
SUCCESS_CHECK_COMMAND='curl -f http://localhost:8080/health'
SUCCESS_CHECK_DELAY=15

# Send notification on crash
CRASH_COMMAND='curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK -d "{\"text\":\"myapp crashed\"}"'
CRASH_RESTART_MAX=5
```

### Service States

- **running** - Service is active and healthy
- **stopped** - Service is not running
- **starting** - Service is in the process of starting
- **crashed** - Service has crashed and exceeded restart limit

### Directory Structure

```
wappman/
├── wappman              # Main entry point
└── lib/
    ├── app.sh          # Application lifecycle
    ├── commands.sh     # CLI command implementations
    ├── config.sh       # Configuration management
    ├── health.sh       # Health checker
    ├── hooks.sh        # Post-start and crash hooks
    ├── log.sh          # Logging utilities
    ├── state.sh        # State management
    ├── status.sh       # Status utilities
    └── watcher.sh      # File watcher
```

### License

MIT License - See LICENSE file for details

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 繁體中文

### 概述

**wappman** 是一個用於 Linux/Unix 系統的用戶級別服務管理器。它可以管理多個服務的生命週期（啟動/停止/重啟），並提供可選的健康檢查（定期進程監控）和文件監視（文件變更時自動重啟）功能。純 Bash 腳本解決方案，除文件監視功能外無需外部依賴。

### 功能特性

- 🚀 **服務生命週期管理** - 輕鬆啟動、停止、重啟服務
- 🔍 **健康監控** - 可配置間隔的定期進程健康檢查
- 👁️ **文件監視** - 配置文件變更時自動重啟服務
- 📊 **狀態報告** - 實時服務狀態和運行時間信息
- 📝 **日誌記錄** - 集中式日誌記錄，支持自動日誌輪替
- 🔄 **崩潰恢復** - 崩潰時自動重啟，可配置重試限制
- 🎯 **啟動後驗證** - 服務啟動後可選的健康檢查命令
- 🔔 **崩潰通知** - 服務崩潰時執行自定義命令
- 📦 **多服務支持** - 同時管理多個服務

### 系統需求

- **Bash** 4.0+
- **inotify-tools**（僅在啟用文件監視時需要）

#### 安裝依賴

**Debian/Ubuntu:**

```bash
sudo apt install inotify-tools
```

**RHEL/CentOS/Fedora:**

```bash
sudo yum install inotify-tools
```

**Arch Linux:**

```bash
sudo pacman -S inotify-tools
```

### 安裝方式

#### 方法一：Wenget

```bash
wenget install wappman
```

#### 方法二：克隆倉庫

```bash
git clone https://github.com/superyngo/wappman.git
cd wappman
chmod +x wappman
```

#### 方法三：下載發布版本

從 [Releases](https://github.com/superyngo/wappman/releases) 頁面下載最新版本並解壓：

```bash
tar -xzf wappman-v*.tar.gz
cd wappman
chmod +x wappman
```

#### 可選：添加到 PATH

```bash
# 在本地 bin 目錄創建符號鏈接
mkdir -p ~/.local/bin
ln -s "$(pwd)/wappman" ~/.local/bin/wappman

# 確保 ~/.local/bin 在 PATH 中
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 快速開始

1. **創建服務配置：**

```bash
./wappman config myapp
```

這會打開一個配置模板。編輯 `APP_EXEC` 字段指向你的應用程序：

```bash
APP_EXEC="/path/to/your/application"
APP_ARGS="--port 8080"
```

2. **啟動服務：**

```bash
./wappman start myapp
```

3. **檢查服務狀態：**

```bash
./wappman status myapp
```

4. **查看日誌：**

```bash
./wappman log myapp
```

### 使用方法

```bash
./wappman <命令> [服務名稱|all]
```

#### 可用命令

| 命令                          | 說明                            |
| ----------------------------- | ------------------------------- |
| `list`                        | 列出所有已配置的服務            |
| `config <名稱>`               | 創建或編輯服務配置              |
| `start <名稱\|all>`           | 啟動服務                        |
| `stop <名稱\|all>`            | 停止服務                        |
| `restart <名稱\|all>`         | 重啟服務                        |
| `restart-app <名稱\|all>`     | 僅重啟應用程序（保持監控）      |
| `restart-monitor <名稱\|all>` | 僅重啟監控（健康檢查/文件監視） |
| `status <名稱\|all>`          | 顯示服務狀態                    |
| `log <名稱>`                  | 查看服務日誌（tail -f）         |
| `log-rotate <名稱\|all>`      | 輪替和清理舊日誌                |
| `clean <名稱\|all>`           | 清理狀態文件                    |
| `del <名稱>`                  | 刪除服務配置                    |

### 配置選項

服務配置存儲在 `~/.config/wappman/<服務名稱>.conf`。以下是主要配置選項：

#### 基本設定

- `APP_EXEC` - **必填**。應用程序可執行文件路徑
- `APP_ARGS` - 應用程序的可選命令行參數
- `STATE_DIR` - 狀態文件目錄（PID、鎖文件等）
- `MANAGER_LOG_FILE` - wappman 日誌文件路徑
- `APP_LOG_FILE` - 應用程序日誌文件路徑（留空則與管理器日誌合併）

#### 健康檢查設定

- `HEALTH_CHECK_INTERVAL` - 健康檢查間隔（秒，0 表示禁用）

#### 文件監視設定

- `WATCH_FILES` - 要監視變更的文件列表（空格分隔）
- `RESTART_FILE` - 修改時觸發重啟的特殊文件

#### 重啟和超時設定

- `RESTART_DELAY` - 重啟前延遲（秒）
- `RESTART_MIN_INTERVAL` - 兩次重啟之間的最小間隔（秒）
- `STOP_TIMEOUT` - 優雅停止的超時時間，超時後強制終止（秒）

#### 崩潰恢復設定

- `SUCCESS_CHECK_COMMAND` - 驗證成功啟動的命令（例如：`curl -f http://localhost:8080/health`）
- `SUCCESS_CHECK_DELAY` - 運行成功檢查前的延遲（秒）
- `CRASH_RESTART_MAX` - 最大重啟嘗試次數（0 表示無限制）
- `CRASH_COMMAND` - 服務崩潰時執行的命令

#### 日誌輪替

- `LOG_RETAIN_DAYS` - 日誌保留天數（默認：7）

### 配置示例

```bash
# myapp.conf
APP_EXEC="/usr/local/bin/myapp"
APP_ARGS="--port 8080 --config /etc/myapp/config.yaml"

# 每 20 分鐘進行健康檢查
HEALTH_CHECK_INTERVAL=1200

# 監視配置文件變更
WATCH_FILES="/etc/myapp/config.yaml"

# 重啟後等待 10 秒
RESTART_DELAY=10

# 驗證服務是否響應
SUCCESS_CHECK_COMMAND='curl -f http://localhost:8080/health'
SUCCESS_CHECK_DELAY=15

# 崩潰時發送通知
CRASH_COMMAND='curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK -d "{\"text\":\"myapp 崩潰了\"}"'
CRASH_RESTART_MAX=5
```

### 服務狀態

- **running** - 服務正在運行且健康
- **stopped** - 服務未運行
- **starting** - 服務正在啟動過程中
- **crashed** - 服務已崩潰並超過重啟限制

### 目錄結構

```
wappman/
├── wappman              # 主入口點
└── lib/
    ├── app.sh          # 應用程序生命週期
    ├── commands.sh     # CLI 命令實現
    ├── config.sh       # 配置管理
    ├── health.sh       # 健康檢查器
    ├── hooks.sh        # 啟動後和崩潰鉤子
    ├── log.sh          # 日誌工具
    ├── state.sh        # 狀態管理
    ├── status.sh       # 狀態工具
    └── watcher.sh      # 文件監視器
```

### 授權協議

MIT License - 詳見 LICENSE 文件

### 貢獻

歡迎貢獻！請隨時提交 Pull Request。
