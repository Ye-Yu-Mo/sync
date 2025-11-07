import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import 'transport/transport.dart';

/// 同步引擎
class SyncEngine {
  final ResilientSftpClient _client;
  final FileTransfer _transfer;

  SyncEngine(this._client) : _transfer = FileTransfer(_client);

  /// 扫描文件变更
  /// Task 7.1 + 7.2: 文件扫描 + 变更检测
  Future<FileChanges> scanChanges(
    String localDir,
    String remoteDir, {
    DateTime? lastSyncTime,
  }) async {
    // 1. 扫描本地文件
    final localFiles = await _scanLocalDirectory(localDir);

    // 2. 扫描远程文件
    final remoteFiles = await _scanRemoteDirectory(remoteDir);

    // 3. 构建哈希表
    final localMap = {for (var f in localFiles) f.relativePath: f};
    final remoteMap = {for (var f in remoteFiles) f.relativePath: f};

    // 4. 检测变更
    final toUpload = <FileInfo>[];
    final toDelete = <FileInfo>[];
    final conflicts = <FileInfo>[];

    // 遍历本地文件，找出需要上传的
    for (var local in localFiles) {
      final remote = remoteMap[local.relativePath];

      if (remote == null) {
        // 新增文件
        toUpload.add(local);
      } else if (local.modifiedTime.isAfter(remote.modifiedTime)) {
        // 本地文件更新
        // Task 7.3: 冲突检测
        if (lastSyncTime != null &&
            remote.modifiedTime.isAfter(lastSyncTime) &&
            local.modifiedTime.isAfter(lastSyncTime)) {
          // 冲突：本地和远程都被修改了
          conflicts.add(local);
        } else {
          toUpload.add(local);
        }
      }
    }

    // 遍历远程文件，找出本地已删除的
    for (var remote in remoteFiles) {
      if (!localMap.containsKey(remote.relativePath)) {
        toDelete.add(remote);
      }
    }

    return FileChanges(
      toUpload: toUpload,
      toDelete: toDelete,
      conflicts: conflicts,
    );
  }

  /// 执行同步（Task 7.4）
  Future<SyncResult> syncChanges(
    FileChanges changes, {
    required String localDir,
    required String remoteDir,
    ProgressCallback? onProgress,
  }) async {
    final startTime = DateTime.now();
    final errors = <String>[];

    int uploadedCount = 0;
    int conflictCount = 0;

    try {
      // 1. 处理冲突文件（重命名远程文件）
      if (changes.conflicts.isNotEmpty) {
        for (var file in changes.conflicts) {
          try {
            final remotePath = p.join(remoteDir, file.relativePath);
            final backupPath = _generateBackupFilename(remotePath);
            await _client.renameFile(remotePath, backupPath);
            conflictCount++;
          } catch (e) {
            errors.add('冲突处理失败 ${file.relativePath}: $e');
          }
        }

        // 冲突文件重命名后，加入上传列表
        for (var file in changes.conflicts) {
          if (!changes.toUpload.contains(file)) {
            changes = FileChanges(
              toUpload: [...changes.toUpload, file],
              toDelete: changes.toDelete,
              conflicts: changes.conflicts,
            );
          }
        }
      }

      // 2. 上传新增/修改文件（4 线程并行）
      if (changes.toUpload.isNotEmpty) {
        final uploadErrors = await _transfer.uploadBatch(
          changes.toUpload,
          localBaseDir: localDir,
          remoteBaseDir: remoteDir,
          onProgress: onProgress,
        );

        uploadedCount = changes.toUpload.length - uploadErrors.length;
        errors.addAll(uploadErrors);
      }
    } catch (e) {
      errors.add('同步执行失败: $e');
    }

    final elapsed = DateTime.now().difference(startTime);

    return SyncResult(
      uploadedCount: uploadedCount,
      deletedCount: 0, // 删除操作由用户确认后单独执行
      conflictCount: conflictCount,
      errors: errors,
      elapsed: elapsed,
    );
  }

  /// 执行删除操作（Task 7.5）
  /// 注意：仅在用户确认后调用
  Future<List<String>> executeDeletions(
    List<FileInfo> files, {
    required String remoteDir,
  }) async {
    return await _transfer.deleteBatch(
      files,
      remoteBaseDir: remoteDir,
    );
  }

  /// 扫描本地目录（Task 7.1）
  Future<List<FileInfo>> _scanLocalDirectory(String localDir) async {
    final files = <FileInfo>[];
    final dir = Directory(localDir);

    if (!await dir.exists()) {
      throw SyncEngineException('本地目录不存在: $localDir');
    }

    try {
      await for (var entity in dir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          final relativePath = p.relative(entity.path, from: localDir);

          files.add(FileInfo(
            relativePath: relativePath,
            size: stat.size,
            modifiedTime: stat.modified,
          ));
        }
      }
    } catch (e) {
      throw SyncEngineException('扫描本地目录失败: $e');
    }

    return files;
  }

  /// 扫描远程目录（Task 7.1）
  Future<List<FileInfo>> _scanRemoteDirectory(String remoteDir) async {
    final files = <FileInfo>[];

    try {
      await _scanRemoteRecursive(remoteDir, '', files);
    } catch (e) {
      throw SyncEngineException('扫描远程目录失败: $e');
    }

    return files;
  }

  /// 递归扫描远程目录
  Future<void> _scanRemoteRecursive(
    String baseDir,
    String currentRelativePath,
    List<FileInfo> files,
  ) async {
    final currentPath = currentRelativePath.isEmpty
        ? baseDir
        : p.join(baseDir, currentRelativePath);

    try {
      final items = await _client.listDirectory(currentPath);

      for (var item in items) {
        // 跳过 . 和 ..
        if (item.name == '.' || item.name == '..') {
          continue;
        }

        final itemRelativePath = currentRelativePath.isEmpty
            ? item.name
            : p.join(currentRelativePath, item.name);

        if (item.isDirectory) {
          // 递归扫描子目录
          await _scanRemoteRecursive(baseDir, itemRelativePath, files);
        } else {
          // 添加文件信息
          files.add(FileInfo(
            relativePath: itemRelativePath,
            size: item.size,
            modifiedTime: item.modifiedTime ?? DateTime.now(),
          ));
        }
      }
    } catch (e) {
      // 目录不存在或权限问题，跳过
      // print('跳过目录 $currentPath: $e');
    }
  }

  /// 生成备份文件名（Task 7.3）
  /// 格式：filename.ext.remote-20250107-153045
  String _generateBackupFilename(String originalPath) {
    final timestamp = DateTime.now();
    final formatted =
        '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}-'
        '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}';

    return '$originalPath.remote-$formatted';
  }

  /// 获取待删除文件列表（用于 UI 显示）
  List<FileInfo> getPendingDeletions(FileChanges changes) {
    return changes.toDelete;
  }

  /// 完整的同步流程（包含所有步骤）
  Future<SyncResult> performFullSync({
    required String localDir,
    required String remoteDir,
    DateTime? lastSyncTime,
    ProgressCallback? onProgress,
    bool autoDelete = false, // 是否自动删除（默认需要用户确认）
  }) async {
    final startTime = DateTime.now();

    try {
      // 1. 扫描变更
      final changes = await scanChanges(
        localDir,
        remoteDir,
        lastSyncTime: lastSyncTime,
      );

      // 2. 执行同步（上传）
      var result = await syncChanges(
        changes,
        localDir: localDir,
        remoteDir: remoteDir,
        onProgress: onProgress,
      );

      // 3. 处理删除（如果允许自动删除）
      if (autoDelete && changes.toDelete.isNotEmpty) {
        final deleteErrors = await executeDeletions(
          changes.toDelete,
          remoteDir: remoteDir,
        );

        result = SyncResult(
          uploadedCount: result.uploadedCount,
          deletedCount: changes.toDelete.length - deleteErrors.length,
          conflictCount: result.conflictCount,
          errors: [...result.errors, ...deleteErrors],
          elapsed: DateTime.now().difference(startTime),
        );
      }

      return result;
    } catch (e) {
      return SyncResult.failure(
        errors: ['同步失败: $e'],
        elapsed: DateTime.now().difference(startTime),
      );
    }
  }
}

/// 同步引擎异常
class SyncEngineException implements Exception {
  final String message;

  const SyncEngineException(this.message);

  @override
  String toString() => 'SyncEngineException: $message';
}
