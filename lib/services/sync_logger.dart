import 'dart:io';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'storage/storage_service.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 同步日志记录器
class SyncLogger {
  final String taskId;
  final String taskName;
  final StorageService _storage;
  String? _logFilePath;
  IOSink? _logSink;

  SyncLogger({
    required this.taskId,
    required this.taskName,
    required StorageService storage,
  }) : _storage = storage;

  /// 初始化日志文件
  Future<void> initialize() async {
    final logDir = await _storage.getLogDirectory();
    final timestamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    _logFilePath = '$logDir/$taskId-$timestamp.log';

    final file = File(_logFilePath!);
    _logSink = file.openWrite(mode: FileMode.append);

    // 写入日志头
    await _writeLog(LogLevel.info, '========================================');
    await _writeLog(LogLevel.info, '任务: $taskName');
    await _writeLog(LogLevel.info, '任务ID: $taskId');
    await _writeLog(LogLevel.info, '开始时间: ${_formatDateTime(DateTime.now())}');
    await _writeLog(LogLevel.info, '========================================');
  }

  /// 记录信息日志
  Future<void> logInfo(String message) async {
    await _writeLog(LogLevel.info, message);
  }

  /// 记录警告日志
  Future<void> logWarning(String message) async {
    await _writeLog(LogLevel.warning, message);
  }

  /// 记录错误日志
  Future<void> logError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write('\n  错误详情: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n  堆栈跟踪:\n${_sanitizeStackTrace(stackTrace)}');
    }
    await _writeLog(LogLevel.error, buffer.toString());
  }

  /// 记录调试日志
  Future<void> logDebug(String message) async {
    await _writeLog(LogLevel.debug, message);
  }

  /// 记录同步开始
  Future<void> logSyncStart({
    required String localDir,
    required String remoteDir,
  }) async {
    await _writeLog(LogLevel.info, '开始同步');
    await _writeLog(LogLevel.info, '  本地目录: $localDir');
    await _writeLog(LogLevel.info, '  远程目录: $remoteDir');
  }

  /// 记录同步结果
  Future<void> logSyncResult(SyncResult result) async {
    await _writeLog(LogLevel.info, '同步完成');
    await _writeLog(LogLevel.info, '  上传文件数: ${result.uploadedCount}');
    await _writeLog(LogLevel.info, '  删除文件数: ${result.deletedCount}');
    await _writeLog(LogLevel.info, '  冲突文件数: ${result.conflictCount}');
    await _writeLog(LogLevel.info, '  耗时: ${result.elapsed.inSeconds} 秒');

    if (result.errors.isNotEmpty) {
      await _writeLog(LogLevel.error, '  错误数量: ${result.errors.length}');
      for (var i = 0; i < result.errors.length; i++) {
        await _writeLog(LogLevel.error, '    ${i + 1}. ${result.errors[i]}');
      }
    }
  }

  /// 记录文件操作
  Future<void> logFileOperation(
    String operation,
    String filePath, {
    bool success = true,
    String? error,
  }) async {
    final status = success ? '成功' : '失败';
    final message = '$operation: $filePath [$status]';

    if (success) {
      await _writeLog(LogLevel.info, message);
    } else {
      await _writeLog(LogLevel.error, '$message - $error');
    }
  }

  /// 写入日志
  Future<void> _writeLog(LogLevel level, String message) async {
    if (_logSink == null) {
      return;
    }

    final timestamp = _formatDateTime(DateTime.now());
    final levelStr = level.name.toUpperCase().padRight(7);
    final sanitizedMessage = _sanitize(message);

    _logSink!.writeln('[$timestamp] $levelStr: $sanitizedMessage');
    await _logSink!.flush();
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  /// 日志脱敏（移除敏感信息）
  String _sanitize(String message) {
    var sanitized = message;

    // 移除密码
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'password[=:]\s*\S+', caseSensitive: false),
      (match) => 'password=***',
    );

    sanitized = sanitized.replaceAllMapped(
      RegExp(r'pass[=:]\s*\S+', caseSensitive: false),
      (match) => 'pass=***',
    );

    // 移除 token
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'token[=:]\s*\S+', caseSensitive: false),
      (match) => 'token=***',
    );

    return sanitized;
  }

  /// 脱敏堆栈跟踪
  String _sanitizeStackTrace(StackTrace stackTrace) {
    return _sanitize(stackTrace.toString());
  }

  /// 关闭日志文件
  Future<void> close() async {
    await _writeLog(LogLevel.info, '========================================');
    await _writeLog(LogLevel.info, '结束时间: ${_formatDateTime(DateTime.now())}');
    await _writeLog(LogLevel.info, '========================================');

    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
  }

  /// 获取日志文件路径
  String? get logFilePath => _logFilePath;

  /// 删除旧日志（保留最近 N 天）
  static Future<void> cleanOldLogs(
    StorageService storage, {
    int keepDays = 7,
  }) async {
    try {
      final logDir = await storage.getLogDirectory();
      final dir = Directory(logDir);

      if (!await dir.exists()) {
        return;
      }

      final cutoffDate = DateTime.now().subtract(Duration(days: keepDays));

      await for (var entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.log')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // 清理失败不影响主流程
    }
  }

  /// 获取所有日志文件
  static Future<List<File>> getAllLogs(StorageService storage) async {
    final logDir = await storage.getLogDirectory();
    final dir = Directory(logDir);

    if (!await dir.exists()) {
      return [];
    }

    final logs = <File>[];
    await for (var entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.log')) {
        logs.add(entity);
      }
    }

    // 按修改时间倒序排序
    logs.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.modified.compareTo(aStat.modified);
    });

    return logs;
  }

  /// 读取日志内容
  static Future<String> readLog(File logFile) async {
    return await logFile.readAsString();
  }
}

/// 同步错误封装
class SyncError {
  final SyncErrorType type;
  final String message;
  final String? filePath;
  final Object? originalError;
  final StackTrace? stackTrace;

  const SyncError({
    required this.type,
    required this.message,
    this.filePath,
    this.originalError,
    this.stackTrace,
  });

  /// 从异常创建
  factory SyncError.fromException(
    Exception exception, {
    String? filePath,
    StackTrace? stackTrace,
  }) {
    SyncErrorType type = SyncErrorType.unknown;
    String message = exception.toString();

    // 根据异常类型判断错误类型
    if (exception is SocketException || message.contains('network')) {
      type = SyncErrorType.networkError;
    } else if (message.contains('auth') || message.contains('password')) {
      type = SyncErrorType.authError;
    } else if (message.contains('permission')) {
      type = SyncErrorType.permissionError;
    } else if (message.contains('disk') || message.contains('space')) {
      type = SyncErrorType.diskFullError;
    } else if (message.contains('not found') || message.contains('no such')) {
      type = SyncErrorType.fileNotFound;
    }

    return SyncError(
      type: type,
      message: message,
      filePath: filePath,
      originalError: exception,
      stackTrace: stackTrace,
    );
  }

  /// 获取用户友好的错误提示
  String getUserMessage() {
    return type.userMessage;
  }

  @override
  String toString() {
    final buffer = StringBuffer('SyncError(${type.name}): $message');
    if (filePath != null) {
      buffer.write(' [file: $filePath]');
    }
    return buffer.toString();
  }
}
