# sftp-sync-manager - Requirements Document

A cross-platform Flutter-based SFTP sync manager (macOS & Windows) that handles multiple local-to-remote directory sync tasks with background scheduling, deletion confirmation, and conflict resolution

## Background

FileBrowser 云盘架在服务器 `/data/<user>` 目录下，但不支持本地文件同步到服务器。现有 shell 脚本（sync.sh/sync.ps1）依赖系统级定时任务，配置繁琐且无法动态管理多个同步任务。

**现有脚本的问题：**
- 删除操作无确认，风险高
- 单任务模式，无法管理多个目录
- 依赖系统级服务（LaunchAgent/Task Scheduler）
- 无 GUI 配置界面

## Core Features

### 1. 多任务管理
- 支持创建、编辑、删除多个同步任务
- 每个任务包含：
  - 任务名称（用户自定义）
  - 本地目录路径
  - 远程目录路径（相对于 `/data/<user>`）
  - 同步间隔（分钟）
  - 启用/禁用状态

### 2. Push-Only 同步模式
- 单向同步：本地 → 远程
- 操作类型：
  - **新增/修改**：直接推送到远程
  - **删除**：必须显示确认弹窗（类似 Windows 删除确认）
    - 列出所有待删除文件
    - 显示文件数量和总大小
    - 用户可选择"确认删除"或"取消"

### 3. 冲突处理
- 远程文件被外部修改时，保留多份副本：
  - 原文件：`filename.ext`
  - 远程版本：`filename.ext.remote-20250107-153045`
  - 本地版本：正常上传为 `filename.ext`

### 4. 后台定时同步
- 使用 Flutter WorkManager 实现
- 要求：应用保持后台运行（进程存在）
- 定时触发同步任务（用户配置的间隔）
- 同步时显示通知（可选）

### 5. 断点重传
- 大文件上传失败时，支持从断点继续
- 使用 SFTP resume 功能

### 6. 服务器配置
- 单例配置（所有任务共享）：
  - 主机地址：`23.94.111.42`
  - 端口：`22`
  - SSH 用户：`syncuser`
  - SSH 密码：`nba0981057309`
  - 远程基础目录：`/data/<user>` （用户选择 yachen 或 xulei）

## User Stories

### 基础管理
- **作为用户**，我想创建多个同步任务，以便管理不同项目目录的同步
- **作为用户**，我想在 GUI 界面配置任务，而不是编辑脚本文件
- **作为用户**，我想暂停/恢复某个任务，而不影响其他任务

### 安全性
- **作为用户**，我想在删除远程文件前看到确认提示，避免误操作
- **作为用户**，我想看到将要删除的文件列表，确认无误后再执行

### 自动化
- **作为用户**，我想设置定时同步，保持后台运行时自动执行
- **作为用户**，我想收到同步完成通知（成功/失败）

### 可靠性
- **作为用户**，我想在网络中断后，大文件能断点续传，不用重新上传
- **作为用户**，我想在远程文件冲突时，保留多个版本，不丢失数据

## Acceptance Criteria

### 任务管理
- [ ] 可以创建新任务，填写名称、本地目录、远程子目录、同步间隔
- [ ] 可以编辑现有任务的所有配置
- [ ] 可以删除任务（删除配置，不删除已同步文件）
- [ ] 可以启用/禁用任务
- [ ] 任务列表显示每个任务的最后同步时间和状态

### 同步功能
- [ ] 手动触发同步按钮，立即执行一次同步
- [ ] 自动定时同步（后台运行时）
- [ ] 新增/修改文件自动推送到远程
- [ ] 删除操作显示确认弹窗：
  - [ ] 列出所有待删除文件的完整路径
  - [ ] 显示文件数量（如"将删除 15 个文件"）
  - [ ] 显示总大小（如"总计 2.3 MB"）
  - [ ] 提供"确认删除"和"取消"按钮
- [ ] 远程文件冲突时，生成带时间戳的备份文件

### 网络可靠性
- [ ] 大文件（>10MB）支持断点续传
- [ ] 网络异常时显示错误提示
- [ ] 同步失败后可重试

### 后台任务
- [ ] 应用进入后台时，定时任务继续运行
- [ ] 同步完成显示系统通知
- [ ] 通知中显示同步结果（成功上传 X 个文件，失败 Y 个）

### 配置兼容性
- [ ] 兼容现有脚本的 JSON 配置格式（`app.json`）
- [ ] 配置文件存储在 `~/.sftp_sync/app.json`（macOS）或 `%LOCALAPPDATA%\SftpSync\app.json`（Windows）

## Non-functional Requirements

### Performance
- 同步前扫描本地目录，大目录（10k+ 文件）需在 5 秒内完成
- 使用并行上传（4 线程），提升大文件传输速度
- UI 不阻塞：同步在后台线程执行

### Security
- SSH 密码存储使用 Flutter Secure Storage（加密存储）
- 日志文件不包含明文密码
- 仅支持 SFTP（不支持不安全的 FTP）

### Compatibility
- **平台支持（必须）**：
  - macOS 10.14+
  - Windows 10/11
- **平台支持（可选）**：Linux
- **Flutter 版本**：>=3.0.0
- **依赖库**：
  - `dartssh2` 或 `ssh2` - SFTP 客户端
  - `workmanager` - 后台任务调度
  - `flutter_secure_storage` - 密码加密存储
  - `path_provider` - 配置文件路径

### Usability
- 用户无需手动安装 lftp、WinSCP 等外部工具
- 配置界面提供目录选择器（不手动输入路径）
- 错误提示清晰，提供解决建议（如"网络连接失败，请检查 VPN"）

### Maintainability
- 日志文件按任务 ID 和时间戳分离：`logs/<taskId>-20250107-153045.log`
- 代码结构清晰：UI 层、业务逻辑层、SFTP 客户端层分离
