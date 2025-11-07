import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import '../../models/models.dart';
import 'sftp_client.dart';

/// 重试策略配置
class RetryConfig {
  final int maxAttempts;
  final Duration Function(int attempt) backoff;

  const RetryConfig({
    required this.maxAttempts,
    required this.backoff,
  });

  /// 网络错误重试策略：重试 3 次，指数退避（1s, 2s, 4s）
  static const networkRetry = RetryConfig(
    maxAttempts: 3,
    backoff: _exponentialBackoff,
  );

  /// 文件锁错误重试策略：重试 5 次，固定间隔（500ms）
  static const fileLockRetry = RetryConfig(
    maxAttempts: 5,
    backoff: _fixedBackoff,
  );

  /// 认证错误不重试
  static const authRetry = RetryConfig(
    maxAttempts: 1,
    backoff: _noBackoff,
  );

  /// 指数退避：1s, 2s, 4s
  static Duration _exponentialBackoff(int attempt) {
    return Duration(seconds: 1 << (attempt - 1)); // 2^(attempt-1)
  }

  /// 固定间隔：500ms
  static Duration _fixedBackoff(int attempt) {
    return const Duration(milliseconds: 500);
  }

  /// 无退避
  static Duration _noBackoff(int attempt) {
    return Duration.zero;
  }
}

/// 带重试机制的 SFTP 客户端
class ResilientSftpClient {
  final SftpService _client = SftpService();

  /// 是否已连接
  bool get isConnected => _client.isConnected;

  /// 连接到服务器（带重试）
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    return _retry(
      () => _client.connect(
        host: host,
        port: port,
        username: username,
        password: password,
      ),
      RetryConfig.authRetry, // 认证错误不重试
    );
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _client.disconnect();
  }

  /// 列出目录（带重试）
  Future<List<RemoteFile>> listDirectory(String remotePath) async {
    return _retry(
      () => _client.listDirectory(remotePath),
      RetryConfig.networkRetry,
    );
  }

  /// 获取文件状态（带重试）
  Future<SftpFileAttrs?> statFile(String remotePath) async {
    return _retry(
      () => _client.statFile(remotePath),
      RetryConfig.networkRetry,
    );
  }

  /// 上传文件（带重试）
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    bool resume = true,
    ProgressCallback? onProgress,
  }) async {
    return _retry(
      () => _client.uploadFile(
        localPath,
        remotePath,
        resume: resume,
        onProgress: onProgress,
      ),
      RetryConfig.networkRetry,
    );
  }

  /// 删除文件（带重试）
  Future<void> deleteFile(String remotePath) async {
    return _retry(
      () => _client.deleteFile(remotePath),
      RetryConfig.networkRetry,
    );
  }

  /// 重命名文件（带重试）
  Future<void> renameFile(String oldPath, String newPath) async {
    return _retry(
      () => _client.renameFile(oldPath, newPath),
      RetryConfig.networkRetry,
    );
  }

  /// 创建目录（带重试）
  Future<void> createDirectory(String remotePath) async {
    return _retry(
      () => _client.createDirectory(remotePath),
      RetryConfig.networkRetry,
    );
  }

  /// 通用重试逻辑
  Future<T> _retry<T>(
    Future<T> Function() action,
    RetryConfig config,
  ) async {
    int attempt = 0;
    Exception? lastError;

    while (attempt < config.maxAttempts) {
      attempt++;
      try {
        return await action();
      } on SftpException catch (e) {
        lastError = e;

        // 认证错误不重试
        if (e.type == SyncErrorType.authError) {
          rethrow;
        }

        // 最后一次尝试失败，抛出异常
        if (attempt >= config.maxAttempts) {
          rethrow;
        }

        // 等待后重试
        final delay = config.backoff(attempt);
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());

        // 最后一次尝试失败，抛出异常
        if (attempt >= config.maxAttempts) {
          rethrow;
        }

        // 等待后重试
        final delay = config.backoff(attempt);
        if (delay > Duration.zero) {
          await Future.delayed(delay);
        }
      }
    }

    // 不应该到达这里
    throw lastError ?? Exception('重试失败');
  }
}
