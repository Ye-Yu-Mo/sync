import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../../models/models.dart';

/// 进度回调函数
typedef ProgressCallback = void Function(int uploaded, int total);

/// 远程文件信息
class RemoteFile {
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedTime;

  const RemoteFile({
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modifiedTime,
  });
}

/// SFTP 服务（包装 dartssh2 的 SftpClient）
class SftpService {
  SSHClient? _sshClient;
  SftpClient? _sftpSession;
  String? _currentHost;
  int? _currentPort;

  /// 是否已连接
  bool get isConnected => _sshClient != null && _sftpSession != null;

  /// 连接到 SFTP 服务器
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    // 如果已连接到同一服务器，复用连接
    if (isConnected && _currentHost == host && _currentPort == port) {
      return;
    }

    // 断开旧连接
    await disconnect();

    try {
      // 创建 SSH 客户端
      final socket = await SSHSocket.connect(host, port);
      _sshClient = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      // 创建 SFTP 会话
      _sftpSession = await _sshClient!.sftp();

      _currentHost = host;
      _currentPort = port;
    } catch (e) {
      _sshClient = null;
      _sftpSession = null;
      _currentHost = null;
      _currentPort = null;
      throw SftpException(SyncErrorType.authError, '连接失败: $e');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _sftpSession?.close();
    _sshClient?.close();
    await _sshClient?.done;

    _sftpSession = null;
    _sshClient = null;
    _currentHost = null;
    _currentPort = null;
  }

  /// 列出目录内容
  Future<List<RemoteFile>> listDirectory(String remotePath) async {
    _ensureConnected();

    try {
      final items = await _sftpSession!.listdir(remotePath);
      return items.map((item) {
        return RemoteFile(
          name: item.filename,
          isDirectory: item.attr.isDirectory,
          size: item.attr.size ?? 0,
          modifiedTime: item.attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  item.attr.modifyTime! * 1000)
              : null,
        );
      }).toList();
    } catch (e) {
      throw SftpException(SyncErrorType.networkError, '列出目录失败: $e');
    }
  }

  /// 获取文件状态
  Future<SftpFileAttrs?> statFile(String remotePath) async {
    _ensureConnected();

    try {
      return await _sftpSession!.stat(remotePath);
    } catch (e) {
      // 文件不存在
      return null;
    }
  }

  /// 上传文件（支持断点续传）
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    bool resume = true,
    ProgressCallback? onProgress,
  }) async {
    _ensureConnected();

    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw SftpException(
          SyncErrorType.fileNotFound, '本地文件不存在: $localPath');
    }

    final totalSize = await localFile.length();
    int uploadedSize = 0;

    try {
      // 检查远程文件是否存在（断点续传）
      if (resume) {
        final remoteStat = await statFile(remotePath);
        if (remoteStat != null && remoteStat.size != null) {
          uploadedSize = remoteStat.size!;

          // 如果远程文件已完整，跳过上传
          if (uploadedSize >= totalSize) {
            onProgress?.call(totalSize, totalSize);
            return;
          }
        }
      }

      // 打开本地文件
      final file = await _sftpSession!.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            (resume ? SftpFileOpenMode.append : SftpFileOpenMode.truncate),
      );

      // 读取本地文件并上传
      final localStream = localFile.openRead(uploadedSize);
      await for (var chunk in localStream) {
        await file.write(Stream.value(Uint8List.fromList(chunk)));
        uploadedSize += chunk.length;
        onProgress?.call(uploadedSize, totalSize);
      }

      await file.close();
    } catch (e) {
      throw SftpException(SyncErrorType.networkError, '上传失败: $e');
    }
  }

  /// 删除文件
  Future<void> deleteFile(String remotePath) async {
    _ensureConnected();

    try {
      await _sftpSession!.remove(remotePath);
    } catch (e) {
      throw SftpException(SyncErrorType.networkError, '删除失败: $e');
    }
  }

  /// 重命名文件（用于冲突处理）
  Future<void> renameFile(String oldPath, String newPath) async {
    _ensureConnected();

    try {
      await _sftpSession!.rename(oldPath, newPath);
    } catch (e) {
      throw SftpException(SyncErrorType.networkError, '重命名失败: $e');
    }
  }

  /// 创建目录（递归）
  Future<void> createDirectory(String remotePath) async {
    _ensureConnected();

    try {
      await _sftpSession!.mkdir(remotePath);
    } catch (e) {
      // 目录可能已存在，忽略错误
    }
  }

  /// 确保已连接
  void _ensureConnected() {
    if (!isConnected) {
      throw SftpException(SyncErrorType.networkError, '未连接到 SFTP 服务器');
    }
  }
}

/// SFTP 异常
class SftpException implements Exception {
  final SyncErrorType type;
  final String message;

  const SftpException(this.type, this.message);

  @override
  String toString() => 'SftpException: $message';
}
