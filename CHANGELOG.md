# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/superyngo/wappman/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/superyngo/wappman/releases/tag/v1.0.0
