import '../models/models.dart';

/// 规范化远程基础目录，确保以 `/` 开头且无多余结尾斜杠。
String normalizeRemoteBase(String base) {
  if (base.trim().isEmpty) {
    return '/';
  }
  var normalized = base.trim().replaceAll('\\', '/');
  if (!normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  while (normalized.endsWith('/') && normalized.length > 1) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

/// 拼接远程路径，自动处理多余的 `/`。
String joinRemotePath(String base, String relative) {
  final trimmedBase =
      base.endsWith('/') && base.length > 1 ? base.substring(0, base.length - 1) : base;
  final trimmedRelative = relative.trim();
  if (trimmedRelative.isEmpty || trimmedRelative == '/') {
    return trimmedBase;
  }
  final normalizedRelative =
      trimmedRelative.startsWith('/') ? trimmedRelative.substring(1) : trimmedRelative;
  return '$trimmedBase/$normalizedRelative';
}

/// 构建同步任务的远程完整路径：remoteBase/<fileBrowserUser>/<remoteDir>
String buildRemoteTaskPath(ServerConfig server, SyncTask task) {
  final base = normalizeRemoteBase(server.remoteBaseDir);
  final userSegment = task.fileBrowserUser.trim().replaceAll('/', '');
  final userBase = userSegment.isEmpty ? base : '$base/$userSegment';
  return joinRemotePath(userBase, task.remoteDir);
}
