# sftp-sync-manager - Design Document

## Overview

**设计哲学：数据结构驱动，消除特殊情况**

基于 Linus Torvalds 的"好品味"原则：
1. **数据结构第一**：先设计清晰的数据模型，代码自然简洁
2. **消除边界情况**：统一的文件操作流程，不区分"新增"vs"修改"
3. **三层架构**：UI 层、业务逻辑层、SFTP 传输层严格分离
4. **实用主义**：拒绝过度设计，解决真实问题

**核心设计决策：**
- **配置文件**：兼容现有脚本的 JSON 格式，存储在用户目录
- **后台任务**：使用 WorkManager，不依赖系统级服务
- **删除策略**：扫描 → 用户确认 → 执行，统一流程
- **冲突处理**：生成带时间戳的备份，无需用户介入

## Architecture

### 三层架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  (Flutter UI - Material Design)                              │
│  - TaskListScreen (任务列表)                                  │
│  - TaskEditScreen (创建/编辑任务)                              │
│  - SyncProgressScreen (同步进度)                              │
│  - DeletionConfirmDialog (删除确认弹窗)                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     Business Logic Layer                     │
│  (核心业务逻辑 - Pure Dart)                                    │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │  TaskManager    │  │  SyncEngine      │                  │
│  │  - CRUD 任务    │  │  - 文件扫描      │                  │
│  │  - 加载/保存    │  │  - 变更检测      │                  │
│  │    配置文件     │  │  - 冲突处理      │                  │
│  └─────────────────┘  └──────────────────┘                  │
│                                                               │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │  SchedulerService│  │  StorageService  │                  │
│  │  - WorkManager   │  │  - 配置持久化    │                  │
│  │  - 定时触发      │  │  - 密码加密      │                  │
│  └─────────────────┘  └──────────────────┘                  │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     Transport Layer                          │
│  (SFTP 传输 - dartssh2)                                       │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │  SftpClient     │  │  FileTransfer    │                  │
│  │  - 连接管理      │  │  - 上传/下载     │                  │
│  │  - 会话保持      │  │  - 断点续传      │                  │
│  │  - 错误重试      │  │  - 进度回调      │                  │
│  └─────────────────┘  └──────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### 数据流

```
用户操作 → UI Layer → Business Logic → Transport Layer → SFTP Server
                           ↓
                     配置文件 (JSON)
                           ↓
                     WorkManager 后台调度
```

## Components and Interfaces

### 1. Presentation Layer

#### TaskListScreen
```dart
class TaskListScreen extends StatefulWidget {
  // 功能：显示所有同步任务列表
  // - 显示任务名称、状态、最后同步时间
  // - 提供"新建任务"按钮
  // - 提供"手动同步"按钮（每个任务）
  // - 提供"启用/禁用"开关
}
```

#### TaskEditScreen
```dart
class TaskEditScreen extends StatefulWidget {
  // 功能：创建或编辑任务
  // - 输入任务名称
  // - 选择本地目录（目录选择器）
  // - 输入远程子目录（相对路径）
  // - 设置同步间隔（分钟）
  // - 选择 FileBrowser 用户（yachen/xulei）
}
```

#### DeletionConfirmDialog
```dart
class DeletionConfirmDialog extends StatelessWidget {
  final List<FileInfo> filesToDelete;
  final int totalSize;

  // 功能：Windows 风格的删除确认弹窗
  // - 列出所有待删除文件的完整路径
  // - 显示"将删除 X 个文件（共 Y MB）"
  // - 提供"确认删除"和"取消"按钮
}
```

### 2. Business Logic Layer

#### TaskManager
```dart
class TaskManager {
  // 数据结构：List<SyncTask>

  Future<List<SyncTask>> loadTasks();
  Future<void> saveTasks(List<SyncTask> tasks);
  Future<void> createTask(SyncTask task);
  Future<void> updateTask(String taskId, SyncTask task);
  Future<void> deleteTask(String taskId);
  Future<void> toggleTask(String taskId, bool enabled);
}
```

#### SyncEngine
```dart
class SyncEngine {
  // 核心同步引擎

  // 扫描本地目录，返回文件变更列表
  Future<FileChanges> scanChanges(String localDir, String remoteDir);

  // 执行同步（不包含删除）
  Future<SyncResult> syncChanges(FileChanges changes);

  // 返回待删除文件列表（需用户确认）
  List<FileInfo> getPendingDeletions(FileChanges changes);

  // 执行删除操作（用户确认后）
  Future<void> executeDeletions(List<FileInfo> files);

  // 冲突处理：生成带时间戳的备份文件名
  String resolveConflict(String originalPath);
}
```

**关键设计：消除特殊情况**
```dart
// ❌ 糟糕的设计：区分新增和修改
if (file.isNew) {
  uploadNewFile(file);
} else if (file.isModified) {
  uploadModifiedFile(file);
}

// ✅ 好品味：统一处理
// 数据结构：FileChange { path, localMtime, remoteMtime }
// 只要 localMtime > remoteMtime，就上传
for (change in changes.needsUpload) {
  upload(change.path);  // 无条件上传，SFTP 自动覆盖
}
```

#### SchedulerService
```dart
class SchedulerService {
  // 使用 WorkManager 实现后台定时任务

  Future<void> scheduleTask(String taskId, int intervalMinutes);
  Future<void> cancelTask(String taskId);

  // WorkManager 回调入口
  static void backgroundSyncCallback() {
    // 加载配置 → 执行同步 → 显示通知
  }
}
```

#### StorageService
```dart
class StorageService {
  // 配置文件管理

  Future<String> getConfigPath();
  // macOS: ~/.sftp_sync/app.json
  // Windows: %LOCALAPPDATA%\SftpSync\app.json

  Future<AppConfig> loadConfig();
  Future<void> saveConfig(AppConfig config);

  // 密码加密存储
  Future<void> savePassword(String password);
  Future<String> loadPassword();
}
```

### 3. Transport Layer

#### SftpClient
```dart
class SftpClient {
  final SSHClient _sshClient;
  SftpClient? _sftpSession;

  // 连接管理
  Future<void> connect(ServerConfig config);
  Future<void> disconnect();

  // 文件操作
  Future<void> uploadFile(String localPath, String remotePath, {
    bool resume = true,  // 断点续传
    ProgressCallback? onProgress,
  });

  Future<void> deleteFile(String remotePath);
  Future<void> renameFile(String oldPath, String newPath);

  Future<List<RemoteFile>> listDirectory(String remotePath);
  Future<FileStat?> statFile(String remotePath);
}
```

#### FileTransfer
```dart
class FileTransfer {
  // 并行上传管理（4 线程）

  Future<void> uploadBatch(List<FileInfo> files, {
    int parallelCount = 4,
    ProgressCallback? onProgress,
  });

  // 断点续传逻辑
  Future<void> resumableUpload(String localPath, String remotePath);
}
```

## Data Models

### 核心数据结构（JSON 兼容）

```dart
// 应用配置文件：~/.sftp_sync/app.json
class AppConfig {
  ServerConfig server;
  List<SyncTask> tasks;
}

// 服务器配置（单例，所有任务共享）
class ServerConfig {
  String host;              // "23.94.111.42"
  int port;                 // 22
  String username;          // "syncuser"
  String password;          // 加密存储
  String remoteBaseDir;     // "/data/{yachen|xulei}"
  String? defaultLocalDir;  // 可选的默认本地目录
}

// 同步任务
class SyncTask {
  String id;                // UUID
  String name;              // 用户自定义任务名
  String localDir;          // 本地目录绝对路径
  String remoteDir;         // 相对于 remoteBaseDir 的路径
  int intervalMinutes;      // 同步间隔
  bool enabled;             // 是否启用
  DateTime? lastSyncTime;   // 上次同步时间
  SyncStatus status;        // idle | syncing | error
}

// 文件变更（扫描结果）
class FileChanges {
  List<FileInfo> toUpload;    // 新增或修改的文件
  List<FileInfo> toDelete;    // 需要删除的文件（待用户确认）
  List<FileInfo> conflicts;   // 冲突文件（需要重命名）
}

// 文件信息
class FileInfo {
  String relativePath;        // 相对路径
  int size;                   // 字节数
  DateTime modifiedTime;      // 修改时间
}

// 同步结果
class SyncResult {
  int uploadedCount;
  int deletedCount;
  int conflictCount;
  List<String> errors;
  Duration elapsed;
}
```

**JSON 配置文件示例**（兼容现有脚本）：
```json
{
  "server": {
    "host": "23.94.111.42",
    "port": 22,
    "username": "syncuser",
    "password": "<encrypted>",
    "remoteBaseDir": "/data/yachen"
  },
  "tasks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "工作文档同步",
      "localDir": "/Users/jasxu/Documents/work",
      "remoteDir": "work",
      "intervalMinutes": 30,
      "enabled": true,
      "lastSyncTime": "2025-01-07T15:30:45Z"
    }
  ]
}
```

## Sync Algorithm

### 文件变更检测（消除边界情况的设计）

```dart
// Linus 式设计：用数据结构消除 if/else
class FileChangeDetector {
  Future<FileChanges> detect(String localDir, String remoteDir) async {
    // 1. 扫描本地所有文件
    final localFiles = await scanLocal(localDir);

    // 2. 扫描远程所有文件
    final remoteFiles = await scanRemote(remoteDir);

    // 3. 构建哈希表（路径 → 文件信息）
    final localMap = {for (var f in localFiles) f.path: f};
    final remoteMap = {for (var f in remoteFiles) f.path: f};

    // 4. 三个集合运算，无特殊情况
    final toUpload = <FileInfo>[];
    final toDelete = <FileInfo>[];
    final conflicts = <FileInfo>[];

    // 遍历本地文件
    for (var local in localFiles) {
      final remote = remoteMap[local.path];
      if (remote == null) {
        toUpload.add(local);  // 新增
      } else if (local.mtime > remote.mtime) {
        // 检查是否有冲突（远程也被修改）
        if (remote.mtime > local.lastSyncTime) {
          conflicts.add(local);
        } else {
          toUpload.add(local);  // 修改
        }
      }
    }

    // 遍历远程文件，找出本地已删除的
    for (var remote in remoteFiles) {
      if (!localMap.containsKey(remote.path)) {
        toDelete.add(remote);
      }
    }

    return FileChanges(
      toUpload: toUpload,
      toDelete: toDelete,
      conflicts: conflicts,
    );
  }
}
```

### 同步流程

```
1. 扫描文件变更
   ↓
2. 处理冲突文件（生成备份文件名）
   ↓
3. 上传新增/修改文件（4 线程并行）
   ↓
4. 如果有删除文件 → 显示确认弹窗
   ├─ 用户确认 → 执行删除
   └─ 用户取消 → 跳过删除
   ↓
5. 更新 lastSyncTime
   ↓
6. 显示同步结果通知
```

## Error Handling

### 错误分类与处理策略

```dart
enum SyncErrorType {
  networkError,      // 网络连接失败
  authError,         // SSH 认证失败
  permissionError,   // 文件权限错误
  diskFullError,     // 远程磁盘已满
  fileNotFound,      // 文件不存在（已被删除）
  unknown,
}

class SyncError {
  SyncErrorType type;
  String message;
  String? filePath;

  // 用户友好的错误提示
  String getUserMessage() {
    switch (type) {
      case SyncErrorType.networkError:
        return "网络连接失败，请检查 VPN 或网络状态";
      case SyncErrorType.authError:
        return "SSH 认证失败，请检查用户名和密码";
      case SyncErrorType.diskFullError:
        return "远程磁盘空间不足，请清理文件后重试";
      // ...
    }
  }
}
```

### 重试策略

```dart
class RetryPolicy {
  // 网络错误：重试 3 次，指数退避（1s, 2s, 4s）
  static const networkRetry = RetryConfig(
    maxAttempts: 3,
    backoff: ExponentialBackoff(baseDelay: 1000),
  );

  // 文件锁错误：重试 5 次，固定间隔（500ms）
  static const fileLockRetry = RetryConfig(
    maxAttempts: 5,
    backoff: FixedBackoff(delay: 500),
  );

  // 认证错误：不重试（立即失败）
  static const authRetry = RetryConfig(maxAttempts: 1);
}
```

### 日志记录

```dart
class SyncLogger {
  final String logFilePath;  // logs/<taskId>-20250107-153045.log

  void logInfo(String message);
  void logError(String message, {Object? error, StackTrace? stackTrace});

  // 日志格式：
  // [2025-01-07 15:30:45] INFO: 开始同步任务: 工作文档同步
  // [2025-01-07 15:30:46] INFO: 扫描到 15 个文件变更
  // [2025-01-07 15:30:50] ERROR: 上传失败: /path/to/file.txt
  //   原因: 网络连接超时
}
```

## Testing Strategy

### 单元测试

```dart
// 核心业务逻辑测试（Pure Dart，无依赖 Flutter）
test('FileChangeDetector - 检测新增文件', () {
  final detector = FileChangeDetector();
  final changes = await detector.detect(localDir, remoteDir);
  expect(changes.toUpload.length, equals(5));
});

test('SyncEngine - 冲突处理生成正确的备份文件名', () {
  final engine = SyncEngine();
  final backup = engine.resolveConflict('file.txt');
  expect(backup, matches(r'file\.txt\.remote-\d{8}-\d{6}'));
});
```

### 集成测试

```dart
// 使用 Mock SFTP 服务器
testWidgets('完整同步流程 - 上传、删除、冲突', (tester) async {
  final mockSftp = MockSftpServer();
  final syncEngine = SyncEngine(client: mockSftp);

  // 1. 扫描变更
  final changes = await syncEngine.scanChanges(localDir, remoteDir);

  // 2. 执行同步
  final result = await syncEngine.syncChanges(changes);

  // 3. 验证结果
  expect(result.uploadedCount, equals(10));
  expect(mockSftp.uploadedFiles.length, equals(10));
});
```

### 平台兼容性测试

```dart
// macOS 和 Windows 路径处理测试
test('路径处理 - macOS', () {
  final path = '/Users/jasxu/Documents/sync/file.txt';
  final relative = getRelativePath(path, '/Users/jasxu/Documents/sync');
  expect(relative, equals('file.txt'));
});

test('路径处理 - Windows', () {
  final path = r'C:\Users\jasxu\Documents\sync\file.txt';
  final relative = getRelativePath(path, r'C:\Users\jasxu\Documents\sync');
  expect(relative, equals('file.txt'));
});
```

### WorkManager 测试

```dart
// 后台任务调度测试
test('SchedulerService - 正确注册后台任务', () async {
  final scheduler = SchedulerService();
  await scheduler.scheduleTask('task-id', intervalMinutes: 30);

  final registered = await Workmanager().isScheduled('task-id');
  expect(registered, isTrue);
});
```

## Security Considerations

### 密码存储

```dart
// 使用 flutter_secure_storage 加密存储
class SecureStorage {
  final storage = FlutterSecureStorage();

  Future<void> savePassword(String password) async {
    await storage.write(key: 'ssh_password', value: password);
  }

  Future<String?> loadPassword() async {
    return await storage.read(key: 'ssh_password');
  }
}
```

### 日志脱敏

```dart
class SyncLogger {
  String sanitize(String message) {
    // 移除日志中的敏感信息
    return message
      .replaceAll(RegExp(r'password[=:]\s*\S+'), 'password=***')
      .replaceAll(RegExp(r'pass[=:]\s*\S+'), 'pass=***');
  }
}
```

## Performance Optimization

### 文件扫描优化

```dart
// 增量扫描：只扫描上次同步后修改的文件
class IncrementalScanner {
  Future<List<FileInfo>> scan(String dir, DateTime lastSyncTime) async {
    final files = <FileInfo>[];
    await for (var entity in Directory(dir).list(recursive: true)) {
      if (entity is File) {
        final stat = await entity.stat();
        if (stat.modified.isAfter(lastSyncTime)) {
          files.add(FileInfo.fromFile(entity, stat));
        }
      }
    }
    return files;
  }
}
```

### 并行上传

```dart
// 使用 Future.wait 实现并行上传
Future<void> uploadBatch(List<FileInfo> files) async {
  final chunks = files.chunked(4);  // 分成 4 个一组
  for (var chunk in chunks) {
    await Future.wait(chunk.map((file) => uploadFile(file)));
  }
}
```

## Deployment

### 构建配置

```yaml
# pubspec.yaml
name: sftp_sync_manager
description: Cross-platform SFTP sync manager for FileBrowser
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'
  flutter: '>=3.0.0'

dependencies:
  flutter:
    sdk: flutter
  dartssh2: ^2.0.0
  workmanager: ^0.5.0
  flutter_secure_storage: ^9.0.0
  path_provider: ^2.1.0
  file_picker: ^6.0.0
  uuid: ^4.0.0
```

### 平台特定配置

**macOS (macos/Runner/DebugProfile.entitlements):**
```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

**Windows (windows/runner/main.cpp):**
```cpp
// 无需特殊配置
```
