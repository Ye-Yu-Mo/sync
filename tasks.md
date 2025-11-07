# sftp-sync-manager - Task List

## Implementation Tasks

### Phase 1: 项目初始化和数据模型

- [x] **1. 项目脚手架**
    - [x] 1.1. 创建 Flutter 项目（macOS & Windows）
        - *Goal*: 初始化 Flutter 项目，配置跨平台支持
        - *Details*:
          - 使用 `flutter create --platforms=macos,windows sftp_sync_manager`
          - 配置 pubspec.yaml 依赖：dartssh2, workmanager, flutter_secure_storage, path_provider, file_picker, uuid
          - 配置最低 SDK 版本：Dart >=3.0.0, Flutter >=3.0.0
        - *Requirements*: 需求文档 - Compatibility

    - [x] 1.2. 配置平台权限
        - *Goal*: 为 macOS 和 Windows 配置必要的系统权限
        - *Details*:
          - macOS: 编辑 `macos/Runner/DebugProfile.entitlements` 添加网络和文件访问权限
          - Windows: 无需特殊配置
        - *Requirements*: 需求文档 - Compatibility

    - [x] 1.3. 项目目录结构
        - *Goal*: 建立清晰的三层架构目录结构
        - *Details*:
          ```
          lib/
          ├── models/          # 数据模型
          ├── services/        # 业务逻辑层
          │   ├── transport/   # 传输层
          │   ├── storage/     # 存储服务
          │   └── scheduler/   # 后台调度
          ├── screens/         # UI 层
          ├── widgets/         # 可复用组件
          └── utils/           # 工具函数
          ```
        - *Requirements*: 设计文档 - Architecture

- [x] **2. 数据模型实现**
    - [x] 2.1. 定义核心数据类
        - *Goal*: 实现所有核心数据模型（AppConfig, ServerConfig, SyncTask, FileChanges, FileInfo, SyncResult）
        - *Details*:
          - 使用 Dart class 实现，支持 JSON 序列化（使用 `json_annotation` 或手写）
          - 每个类实现 `toJson()` 和 `fromJson()` 方法
          - 添加必要的 `copyWith()` 方法用于状态更新
        - *Requirements*: 设计文档 - Data Models

    - [x] 2.2. 枚举类型定义
        - *Goal*: 定义 SyncStatus, SyncErrorType 等枚举
        - *Details*:
          - `enum SyncStatus { idle, syncing, error }`
          - `enum SyncErrorType { networkError, authError, permissionError, diskFullError, fileNotFound, unknown }`
        - *Requirements*: 设计文档 - Data Models

### Phase 2: 传输层实现

- [x] **3. SFTP 客户端**
    - [x] 3.1. SftpClient 基础实现
        - *Goal*: 实现 SFTP 连接管理和基本文件操作
        - *Details*:
          - 使用 `dartssh2` 库
          - 实现 `connect()`, `disconnect()` 方法
          - 实现 `listDirectory()`, `statFile()` 方法
          - 连接池管理（复用 SSH 会话）
        - *Requirements*: 设计文档 - Transport Layer - SftpClient

    - [x] 3.2. 文件上传功能
        - *Goal*: 实现单文件上传，支持断点续传
        - *Details*:
          - `uploadFile(localPath, remotePath, {resume: true, onProgress})`
          - 检查远程文件是否存在，如果存在则断点续传
          - 实现进度回调（已上传字节数/总字节数）
        - *Requirements*: 需求文档 - 断点重传

    - [x] 3.3. 文件删除和重命名
        - *Goal*: 实现删除和重命名操作
        - *Details*:
          - `deleteFile(remotePath)`
          - `renameFile(oldPath, newPath)` - 用于冲突文件重命名
        - *Requirements*: 设计文档 - Transport Layer - SftpClient

    - [x] 3.4. 错误处理和重试
        - *Goal*: 实现网络错误的自动重试机制
        - *Details*:
          - 网络错误：重试 3 次，指数退避（1s, 2s, 4s）
          - 文件锁错误：重试 5 次，固定间隔（500ms）
          - 认证错误：不重试，立即失败
        - *Requirements*: 设计文档 - Error Handling

- [ ] **4. 并行传输**
    - [x] 4.1. FileTransfer 并行上传
        - *Goal*: 实现 4 线程并行上传
        - *Details*:
          - 使用 `Future.wait()` 实现并发上传
          - 将文件列表分成 4 个一组（chunked）
          - 聚合进度回调
        - *Requirements*: 需求文档 - Performance - 并行上传

### Phase 3: 业务逻辑层

- [ ] **5. 配置管理**
    - [x] 5.1. StorageService 实现
        - *Goal*: 实现配置文件的读写
        - *Details*:
          - 使用 `path_provider` 获取配置文件路径
            - macOS: `~/.sftp_sync/app.json`
            - Windows: `%LOCALAPPDATA%\SftpSync\app.json`
          - 实现 `loadConfig()` 和 `saveConfig()` 方法
          - JSON 格式兼容现有脚本
        - *Requirements*: 设计文档 - Business Logic Layer - StorageService

    - [x] 5.2. 密码加密存储
        - *Goal*: 使用 flutter_secure_storage 加密存储 SSH 密码
        - *Details*:
          - `savePassword(password)` - 加密存储
          - `loadPassword()` - 读取解密
          - 配置文件中密码字段存储为 `<encrypted>` 占位符
        - *Requirements*: 需求文档 - Security - 密码加密存储

- [ ] **6. 任务管理**
    - [x] 6.1. TaskManager CRUD 操作
        - *Goal*: 实现任务的增删改查
        - *Details*:
          - `loadTasks()` - 从配置文件加载
          - `createTask(task)` - 创建新任务（生成 UUID）
          - `updateTask(taskId, task)` - 更新任务配置
          - `deleteTask(taskId)` - 删除任务
          - `toggleTask(taskId, enabled)` - 启用/禁用任务
        - *Requirements*: 设计文档 - Business Logic Layer - TaskManager

- [x] **7. 同步引擎**
    - [x] 7.1. 文件扫描功能
        - *Goal*: 扫描本地和远程目录，构建文件列表
        - *Details*:
          - 递归扫描本地目录：`Directory.list(recursive: true)`
          - 远程目录扫描：调用 `SftpClient.listDirectory()`
          - 构建 `Map<path, FileInfo>` 哈希表
        - *Requirements*: 设计文档 - Sync Algorithm

    - [x] 7.2. 文件变更检测
        - *Goal*: 对比本地和远程文件，识别需要同步的文件
        - *Details*:
          - 实现 `FileChangeDetector.detect(localDir, remoteDir)`
          - 返回 `FileChanges(toUpload, toDelete, conflicts)`
          - 使用修改时间（mtime）判断文件是否变更
        - *Requirements*: 设计文档 - Sync Algorithm

    - [x] 7.3. 冲突处理
        - *Goal*: 检测远程文件冲突，生成备份文件名
        - *Details*:
          - 检测条件：`remote.mtime > local.lastSyncTime && local.mtime > remote.mtime`
          - 备份文件名格式：`filename.ext.remote-20250107-153045`
          - 先重命名远程文件，再上传本地文件
        - *Requirements*: 需求文档 - 冲突处理

    - [x] 7.4. 同步执行
        - *Goal*: 执行完整的同步流程
        - *Details*:
          - 上传新增/修改文件（4 线程并行）
          - 返回待删除文件列表（不自动删除）
          - 更新 `lastSyncTime`
          - 返回 `SyncResult`
        - *Requirements*: 设计文档 - Sync Algorithm

    - [x] 7.5. 删除操作（用户确认后）
        - *Goal*: 执行用户确认后的删除操作
        - *Details*:
          - `executeDeletions(List<FileInfo> files)`
          - 批量删除远程文件
          - 记录删除日志
        - *Requirements*: 需求文档 - Push-Only 同步模式 - 删除确认

- [ ] **8. 后台调度**
    - [x] 8.1. SchedulerService 实现
        - *Goal*: 使用 WorkManager 实现定时同步
        - *Details*:
          - `scheduleTask(taskId, intervalMinutes)` - 注册后台任务
          - `cancelTask(taskId)` - 取消后台任务
          - 配置 WorkManager：支持 periodic task
        - *Requirements*: 需求文档 - 后台定时同步

    - [x] 8.2. 后台回调入口
        - *Goal*: 实现 WorkManager 的回调函数
        - *Details*:
          - `backgroundSyncCallback()` - WorkManager 调用的入口
          - 加载配置 → 执行同步 → 显示通知
          - 处理后台异常（网络、权限等）
        - *Requirements*: 需求文档 - 后台定时同步

- [ ] **9. 日志和错误处理**
    - [x] 9.1. SyncLogger 实现
        - *Goal*: 实现日志记录功能
        - *Details*:
          - 日志文件路径：`logs/<taskId>-20250107-153045.log`
          - 日志格式：`[2025-01-07 15:30:45] INFO/ERROR: message`
          - 日志脱敏：移除敏感信息（密码、token）
        - *Requirements*: 设计文档 - Error Handling - 日志记录

    - [x] 9.2. SyncError 错误封装
        - *Goal*: 封装错误类型，提供用户友好的错误提示
        - *Details*:
          - `SyncError(type, message, filePath)`
          - `getUserMessage()` - 返回中文错误提示
        - *Requirements*: 设计文档 - Error Handling

### Phase 4: UI 层实现

- [ ] **10. 任务列表界面**
    - [x] 10.1. TaskListScreen 布局
        - *Goal*: 显示所有同步任务列表
        - *Details*:
          - 使用 `ListView.builder` 显示任务卡片
          - 每个卡片显示：任务名、状态、最后同步时间
          - 提供"新建任务"FloatingActionButton
        - *Requirements*: 设计文档 - Presentation Layer - TaskListScreen

    - [x] 10.2. 任务操作按钮
        - *Goal*: 为每个任务添加操作按钮
        - *Details*:
          - "手动同步"按钮 - 立即执行同步
          - "启用/禁用"开关 - 切换任务状态
          - "编辑"按钮 - 跳转到编辑界面
          - "删除"按钮 - 删除任务（需二次确认）
        - *Requirements*: 设计文档 - Presentation Layer - TaskListScreen

    - [x] 10.3. 任务状态显示
        - *Goal*: 实时显示任务同步状态
        - *Details*:
          - idle: 灰色，显示最后同步时间
          - syncing: 蓝色，显示进度条
          - error: 红色，显示错误图标
        - *Requirements*: 设计文档 - Data Models - SyncTask

- [ ] **11. 任务编辑界面**
    - [x] 11.1. TaskEditScreen 表单
        - *Goal*: 创建或编辑任务的表单界面
        - *Details*:
          - 任务名称：TextFormField
          - 本地目录：目录选择器（file_picker）
          - 远程子目录：TextFormField（相对路径）
          - 同步间隔：NumberInputField（分钟）
          - FileBrowser 用户：DropdownButton（yachen/xulei）
        - *Requirements*: 设计文档 - Presentation Layer - TaskEditScreen

    - [x] 11.2. 表单验证
        - *Goal*: 验证用户输入的有效性
        - *Details*:
          - 任务名称不能为空
          - 本地目录必须存在
          - 同步间隔 >=1 分钟
        - *Requirements*: 设计文档 - Presentation Layer - TaskEditScreen

    - [x] 11.3. 保存任务
        - *Goal*: 保存任务到配置文件
        - *Details*:
          - 调用 `TaskManager.createTask()` 或 `updateTask()`
          - 保存成功后返回任务列表界面
          - 显示成功提示 SnackBar
        - *Requirements*: 设计文档 - Presentation Layer - TaskEditScreen

- [ ] **12. 同步进度界面**
    - [x] 12.1. SyncProgressScreen 实现
        - *Goal*: 显示实时同步进度
        - *Details*:
          - 显示当前正在上传的文件路径
          - 显示总进度：已上传/总文件数
          - 显示上传速度（KB/s）
          - 提供"取消同步"按钮
        - *Requirements*: 设计文档 - Presentation Layer - SyncProgressScreen

- [ ] **13. 删除确认弹窗**
    - [x] 13.1. DeletionConfirmDialog 实现
        - *Goal*: Windows 风格的删除确认弹窗
        - *Details*:
          - 列出所有待删除文件的完整路径（ListView）
          - 显示文件数量和总大小："将删除 15 个文件（共 2.3 MB）"
          - 提供"确认删除"和"取消"按钮
        - *Requirements*: 需求文档 - Push-Only 同步模式 - 删除确认

    - [x] 13.2. 删除执行逻辑
        - *Goal*: 用户确认后执行删除
        - *Details*:
          - 用户点击"确认删除" → 调用 `SyncEngine.executeDeletions()`
          - 用户点击"取消" → 关闭弹窗，跳过删除
          - 显示删除进度和结果
        - *Requirements*: 需求文档 - Push-Only 同步模式 - 删除确认

- [ ] **14. 系统通知**
    - [x] 14.1. 同步完成通知
        - *Goal*: 后台同步完成后显示系统通知
        - *Details*:
          - 使用 `flutter_local_notifications` 插件
          - 通知内容：任务名称、同步结果（成功上传 X 个文件，失败 Y 个）
          - 点击通知跳转到应用
        - *Requirements*: 需求文档 - 后台任务 - 同步完成通知

### Phase 5: 测试和优化

- [ ] **15. 单元测试**
    - [x] 15.1. 数据模型测试
        - *Goal*: 测试 JSON 序列化/反序列化
        - *Details*:
          - 测试 `toJson()` 和 `fromJson()` 正确性
          - 测试 `copyWith()` 方法
        - *Requirements*: 设计文档 - Testing Strategy - 单元测试

    - [x] 15.2. 文件变更检测测试
        - *Goal*: 测试变更检测算法
        - *Details*:
          - 测试新增文件检测
          - 测试修改文件检测
          - 测试删除文件检测
          - 测试冲突文件检测
        - *Requirements*: 设计文档 - Testing Strategy - 单元测试

    - [x] 15.3. 冲突处理测试
        - *Goal*: 测试冲突文件名生成
        - *Details*:
          - 测试备份文件名格式正确性
          - 测试时间戳格式
        - *Requirements*: 设计文档 - Testing Strategy - 单元测试

- [ ] **16. 集成测试**
    - [x] 16.1. Mock SFTP 服务器
        - *Goal*: 搭建 Mock SFTP 服务器用于测试
        - *Details*:
          - 使用 `mockito` 或自建 MockSftpClient
          - 模拟上传、下载、删除操作
        - *Requirements*: 设计文档 - Testing Strategy - 集成测试

    - [x] 16.2. 完整同步流程测试
        - *Goal*: 测试完整的同步流程
        - *Details*:
          - 测试扫描 → 上传 → 删除确认 → 删除执行
          - 测试并行上传
          - 测试断点续传
        - *Requirements*: 设计文档 - Testing Strategy - 集成测试

- [ ] **17. 平台兼容性测试**
    - [x] 17.1. macOS 测试
        - *Goal*: 在 macOS 上测试所有功能
        - *Details*:
          - 测试路径处理（Unix 路径）
          - 测试文件权限
          - 测试后台任务调度
        - *Requirements*: 设计文档 - Testing Strategy - 平台兼容性测试

    - [x] 17.2. Windows 测试
        - *Goal*: 在 Windows 上测试所有功能
        - *Details*:
          - 测试路径处理（Windows 路径）
          - 测试文件权限
          - 测试后台任务调度
        - *Requirements*: 设计文档 - Testing Strategy - 平台兼容性测试

- [ ] **18. 性能优化**
    - [x] 18.1. 文件扫描优化
        - *Goal*: 优化大目录扫描性能
        - *Details*:
          - 实现增量扫描（只扫描 lastSyncTime 后修改的文件）
          - 测试 10k+ 文件的扫描时间（目标 <5 秒）
        - *Requirements*: 需求文档 - Performance - 文件扫描优化

    - [x] 18.2. 并行上传优化
        - *Goal*: 优化并行上传性能
        - *Details*:
          - 测试不同并行度（2, 4, 8 线程）的性能
          - 选择最优并行度
        - *Requirements*: 需求文档 - Performance - 并行上传

### Phase 6: 文档和部署

- [ ] **19. 用户文档**
    - [x] 19.1. README 编写
        - *Goal*: 编写项目 README
        - *Details*:
          - 项目简介
          - 安装和配置步骤
          - 使用说明
          - 常见问题
        - *Requirements*: 需求文档 - Background

    - [x] 19.2. 配置文件示例
        - *Goal*: 提供 app.json 配置文件示例
        - *Details*:
          - 提供完整的 JSON 配置示例
          - 说明每个字段的含义
        - *Requirements*: 设计文档 - Data Models - JSON 配置文件示例

- [ ] **20. 打包和发布**
    - [x] 20.1. macOS 打包
        - *Goal*: 打包 macOS 应用
        - *Details*:
          - `flutter build macos --release`
          - 生成 .app 文件
          - 测试独立运行
        - *Requirements*: 设计文档 - Deployment

    - [x] 20.2. Windows 打包
        - *Goal*: 打包 Windows 应用
        - *Details*:
          - `flutter build windows --release`
          - 生成 .exe 文件
          - 测试独立运行
        - *Requirements*: 设计文档 - Deployment

## Task Dependencies

### 串行依赖
- Phase 1 必须最先完成（项目初始化）
- Phase 2 必须在 Phase 1 之后（传输层依赖项目结构和数据模型）
- Phase 3 必须在 Phase 2 之后（业务逻辑依赖传输层）
- Phase 4 必须在 Phase 3 之后（UI 依赖业务逻辑）
- Phase 5 可以在 Phase 2-4 完成后并行开始
- Phase 6 在所有功能完成后进行

### 可并行任务
- **Phase 2 内部**：3.1-3.4 必须串行，但 4.1 可以在 3.2 完成后并行开始
- **Phase 3 内部**：5.1-5.2（配置管理）和 6.1（任务管理）可并行开发
- **Phase 4 内部**：10（任务列表）、11（任务编辑）、12（同步进度）可并行开发
- **Phase 5 内部**：15（单元测试）、16（集成测试）、17（平台测试）可并行进行

### 关键路径
```
1.1 → 1.2 → 1.3 → 2.1 → 2.2 → 3.1 → 3.2 → 3.3 → 3.4 → 7.1 → 7.2 → 7.3 → 7.4 → 10.1 → 10.2 → 测试 → 打包
```

## Estimated Timeline

### Phase 1: 项目初始化和数据模型
- Task 1: 2 小时
- Task 2: 3 小时
- **小计: 5 小时**

### Phase 2: 传输层实现
- Task 3: 8 小时
- Task 4: 2 小时
- **小计: 10 小时**

### Phase 3: 业务逻辑层
- Task 5: 4 小时
- Task 6: 2 小时
- Task 7: 10 小时
- Task 8: 4 小时
- Task 9: 3 小时
- **小计: 23 小时**

### Phase 4: UI 层实现
- Task 10: 4 小时
- Task 11: 4 小时
- Task 12: 3 小时
- Task 13: 3 小时
- Task 14: 2 小时
- **小计: 16 小时**

### Phase 5: 测试和优化
- Task 15: 4 小时
- Task 16: 4 小时
- Task 17: 4 小时
- Task 18: 3 小时
- **小计: 15 小时**

### Phase 6: 文档和部署
- Task 19: 2 小时
- Task 20: 2 小时
- **小计: 4 小时**

### 总计
**预计总工时: 73 小时**（约 9-10 个工作日，按每天 8 小时计算）

### 里程碑
- **Milestone 1**: Phase 1-2 完成（传输层可用）- Day 2
- **Milestone 2**: Phase 3 完成（核心业务逻辑可用）- Day 5
- **Milestone 3**: Phase 4 完成（完整可用的 UI）- Day 7
- **Milestone 4**: Phase 5 完成（测试通过）- Day 9
- **Milestone 5**: Phase 6 完成（发布）- Day 10
