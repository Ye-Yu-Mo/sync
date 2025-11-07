import 'dart:async';
import 'dart:io';
import '../../models/models.dart';
import 'resilient_sftp_client.dart';
import 'sftp_client.dart';

/// 文件传输管理器（支持并行上传）
class FileTransfer {
  final ResilientSftpClient _client;

  /// 并行上传线程数（默认 4）
  final int parallelCount;

  FileTransfer(this._client, {this.parallelCount = 4});

  /// 批量上传文件（并行）
  Future<List<String>> uploadBatch(
    List<FileInfo> files, {
    required String localBaseDir,
    required String remoteBaseDir,
    ProgressCallback? onProgress,
  }) async {
    if (files.isEmpty) {
      return [];
    }

    final errors = <String>[];
    var totalUploaded = 0;
    final totalSize = files.fold<int>(0, (sum, file) => sum + file.size);

    // 将文件列表分成 parallelCount 个一组
    final chunks = _chunkFiles(files, parallelCount);

    for (var chunk in chunks) {
      // 并行上传每组文件
      final results = await Future.wait(
        chunk.map((file) => _uploadSingleFile(
          file,
          localBaseDir,
          remoteBaseDir,
          (uploaded, _) {
            // 聚合进度
            totalUploaded += uploaded;
            onProgress?.call(totalUploaded, totalSize);
          },
        )),
      );

      // 收集错误
      for (var i = 0; i < results.length; i++) {
        if (results[i] != null) {
          errors.add('${chunk[i].relativePath}: ${results[i]}');
        }
      }
    }

    return errors;
  }

  /// 上传单个文件
  Future<String?> _uploadSingleFile(
    FileInfo fileInfo,
    String localBaseDir,
    String remoteBaseDir,
    ProgressCallback? onProgress,
  ) async {
    try {
      final localPath = _joinPath(localBaseDir, fileInfo.relativePath);
      final remotePath = _joinPath(remoteBaseDir, fileInfo.relativePath);

      // 确保远程目录存在
      final remoteDir = _getParentDir(remotePath);
      if (remoteDir.isNotEmpty) {
        await _ensureRemoteDirectory(remoteDir);
      }

      // 上传文件（支持断点续传）
      await _client.uploadFile(
        localPath,
        remotePath,
        resume: true,
        onProgress: onProgress,
      );

      return null; // 成功
    } catch (e) {
      return e.toString();
    }
  }

  /// 确保远程目录存在（递归创建）
  Future<void> _ensureRemoteDirectory(String remotePath) async {
    try {
      final stat = await _client.statFile(remotePath);
      if (stat != null) {
        return; // 目录已存在
      }
    } catch (_) {
      // 目录不存在，继续创建
    }

    // 递归创建父目录
    final parentDir = _getParentDir(remotePath);
    if (parentDir.isNotEmpty) {
      await _ensureRemoteDirectory(parentDir);
    }

    // 创建当前目录
    try {
      await _client.createDirectory(remotePath);
    } catch (_) {
      // 可能其他线程已创建，忽略错误
    }
  }

  /// 将文件列表分成 n 个一组
  List<List<FileInfo>> _chunkFiles(List<FileInfo> files, int chunkSize) {
    final chunks = <List<FileInfo>>[];
    for (var i = 0; i < files.length; i += chunkSize) {
      final end = (i + chunkSize < files.length) ? i + chunkSize : files.length;
      chunks.add(files.sublist(i, end));
    }
    return chunks;
  }

  /// 拼接路径（跨平台）
  String _joinPath(String base, String relative) {
    // 移除路径中的反斜杠（Windows）并统一为正斜杠（Unix/SFTP）
    final normalizedBase = base.replaceAll('\\', '/');
    final normalizedRelative = relative.replaceAll('\\', '/');

    // 移除 base 末尾的斜杠
    final trimmedBase = normalizedBase.endsWith('/')
        ? normalizedBase.substring(0, normalizedBase.length - 1)
        : normalizedBase;

    // 移除 relative 开头的斜杠
    final trimmedRelative = normalizedRelative.startsWith('/')
        ? normalizedRelative.substring(1)
        : normalizedRelative;

    return '$trimmedBase/$trimmedRelative';
  }

  /// 获取父目录路径
  String _getParentDir(String path) {
    final normalized = path.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash <= 0) {
      return '';
    }
    return normalized.substring(0, lastSlash);
  }

  /// 批量删除文件
  Future<List<String>> deleteBatch(
    List<FileInfo> files, {
    required String remoteBaseDir,
  }) async {
    if (files.isEmpty) {
      return [];
    }

    final errors = <String>[];

    // 删除操作串行执行（避免冲突）
    for (var file in files) {
      try {
        final remotePath = _joinPath(remoteBaseDir, file.relativePath);
        await _client.deleteFile(remotePath);
      } catch (e) {
        errors.add('${file.relativePath}: $e');
      }
    }

    return errors;
  }

  /// 获取本地文件信息
  static Future<FileInfo?> getLocalFileInfo(
    String localPath,
    String baseDir,
  ) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return null;
      }

      final stat = await file.stat();
      final relativePath = _getRelativePath(localPath, baseDir);

      return FileInfo(
        relativePath: relativePath,
        size: stat.size,
        modifiedTime: stat.modified,
      );
    } catch (_) {
      return null;
    }
  }

  /// 获取相对路径
  static String _getRelativePath(String fullPath, String baseDir) {
    final normalizedFull = fullPath.replaceAll('\\', '/');
    final normalizedBase = baseDir.replaceAll('\\', '/');

    if (normalizedFull.startsWith(normalizedBase)) {
      var relative = normalizedFull.substring(normalizedBase.length);
      if (relative.startsWith('/')) {
        relative = relative.substring(1);
      }
      return relative;
    }

    return fullPath;
  }
}
