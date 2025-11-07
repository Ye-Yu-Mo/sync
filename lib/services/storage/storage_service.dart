import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/models.dart';

/// 配置存储服务
class StorageService {
  static const String _passwordKey = 'ssh_password';
  static const String _passwordPlaceholder = '<encrypted>';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 获取配置文件路径
  /// - macOS: ~/.sftp_sync/app.json
  /// - Windows: %LOCALAPPDATA%\SftpSync\app.json
  Future<String> getConfigPath() async {
    if (Platform.isMacOS || Platform.isLinux) {
      // Unix-like 系统：~/.sftp_sync/app.json
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) {
        throw Exception('无法获取用户主目录');
      }
      final configDir = Directory('$home/.sftp_sync');
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }
      return '${configDir.path}/app.json';
    } else if (Platform.isWindows) {
      // Windows: %LOCALAPPDATA%\SftpSync\app.json
      final localAppData =
          Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
      if (localAppData == null || localAppData.isEmpty) {
        throw Exception('无法获取 LOCALAPPDATA 路径');
      }
      final configDir = Directory('$localAppData\\SftpSync');
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }
      return '${configDir.path}\\app.json';
    } else {
      // 其他平台使用应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final configDir = Directory('${appDir.path}/sftp_sync');
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }
      return '${configDir.path}/app.json';
    }
  }

  /// 加载配置
  Future<AppConfig?> loadConfig() async {
    try {
      final configPath = await getConfigPath();
      final file = File(configPath);

      if (!await file.exists()) {
        return null;
      }

      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // 解析配置
      var config = AppConfig.fromJson(jsonData);

      // 从安全存储加载密码
      final password = await loadPassword();
      if (password != null) {
        config = config.copyWith(
          server: config.server.copyWith(password: password),
        );
      }

      return config;
    } catch (e) {
      throw StorageException('加载配置失败: $e');
    }
  }

  /// 保存配置
  Future<void> saveConfig(AppConfig config) async {
    try {
      final configPath = await getConfigPath();
      final file = File(configPath);

      // 保存密码到安全存储
      await savePassword(config.server.password);

      // 配置文件中密码字段使用占位符
      final configWithPlaceholder = config.copyWith(
        server: config.server.copyWith(password: _passwordPlaceholder),
      );

      // 转换为 JSON 并格式化
      final jsonData = configWithPlaceholder.toJson();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);

      // 写入文件
      await file.writeAsString(jsonString);
    } catch (e) {
      throw StorageException('保存配置失败: $e');
    }
  }

  /// 保存密码（加密存储）
  Future<void> savePassword(String password) async {
    try {
      await _secureStorage.write(key: _passwordKey, value: password);
    } catch (e) {
      throw StorageException('保存密码失败: $e');
    }
  }

  /// 加载密码（读取解密）
  Future<String?> loadPassword() async {
    try {
      return await _secureStorage.read(key: _passwordKey);
    } catch (e) {
      throw StorageException('读取密码失败: $e');
    }
  }

  /// 删除密码
  Future<void> deletePassword() async {
    try {
      await _secureStorage.delete(key: _passwordKey);
    } catch (e) {
      throw StorageException('删除密码失败: $e');
    }
  }

  /// 检查配置文件是否存在
  Future<bool> configExists() async {
    try {
      final configPath = await getConfigPath();
      return await File(configPath).exists();
    } catch (_) {
      return false;
    }
  }

  /// 删除配置文件
  Future<void> deleteConfig() async {
    try {
      final configPath = await getConfigPath();
      final file = File(configPath);
      if (await file.exists()) {
        await file.delete();
      }
      await deletePassword();
    } catch (e) {
      throw StorageException('删除配置失败: $e');
    }
  }

  /// 获取日志目录路径
  Future<String> getLogDirectory() async {
    final configPath = await getConfigPath();
    final configDir = File(configPath).parent;
    final logDir = Directory('${configDir.path}/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    return logDir.path;
  }

  /// 创建默认配置
  Future<AppConfig> createDefaultConfig({
    required String host,
    required int port,
    required String username,
    required String password,
    required String remoteBaseDir,
  }) async {
    final config = AppConfig(
      server: ServerConfig(
        host: host,
        port: port,
        username: username,
        password: password,
        remoteBaseDir: remoteBaseDir,
      ),
      tasks: const [],
    );

    await saveConfig(config);
    return config;
  }
}

/// 存储异常
class StorageException implements Exception {
  final String message;

  const StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}
