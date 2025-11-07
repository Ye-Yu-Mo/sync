/// 服务器配置（单例，所有任务共享）
class ServerConfig {
  /// 主机地址
  final String host;

  /// 端口
  final int port;

  /// SSH 用户名
  final String username;

  /// SSH 密码（加密存储）
  final String password;

  /// 远程基础目录（如 /data/yachen）
  final String remoteBaseDir;

  /// 默认本地目录（可选）
  final String? defaultLocalDir;

  const ServerConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.remoteBaseDir,
    this.defaultLocalDir,
  });

  /// 从 JSON 创建
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      password: json['password'] as String,
      remoteBaseDir: json['remoteBaseDir'] as String,
      defaultLocalDir: json['defaultLocalDir'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'remoteBaseDir': remoteBaseDir,
      if (defaultLocalDir != null) 'defaultLocalDir': defaultLocalDir,
    };
  }

  /// 复制并修改部分字段
  ServerConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? remoteBaseDir,
    String? defaultLocalDir,
  }) {
    return ServerConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteBaseDir: remoteBaseDir ?? this.remoteBaseDir,
      defaultLocalDir: defaultLocalDir ?? this.defaultLocalDir,
    );
  }

  @override
  String toString() {
    return 'ServerConfig(host: $host:$port, user: $username, baseDir: $remoteBaseDir)';
  }
}
