wappman              ← 主入口（參數解析：command + SERVICE_NAME、服務名驗證、all 迴圈、互動提示）
lib/
├── log.sh           ← 日誌函式 (log)
├── state.sh         ← 狀態管理 (init_state_dir, read_state, write_state)
├── config.sh        ← 設定載入/驗證/範本 (load_config, create_config_template, preflight_check)
├── hooks.sh         ← 啟動驗證/crash 回呼 (execute_post_start_command, execute_crash_command)
├── status.sh        ← 狀態查詢工具 (is_running, get_uptime)
├── health.sh        ← 健康檢查背景程序 (start_health_checker)
├── watcher.sh       ← 檔案監控 inotify (build_watch_paths, start_inotify_watcher)
├── app.sh           ← 應用生命週期 (start/stop/restart_app, shutdown_on_crash, shutdown_all 等)
└── commands.sh      ← CLI 命令實作 (cmd_start, cmd_stop, cmd_status, cmd_list, cmd_config, cmd_status_all 等)