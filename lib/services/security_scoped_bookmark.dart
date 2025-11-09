import 'dart:io';
import 'package:flutter/services.dart';

/// 目录选择结果（包含可选的安全书签数据）
class DirectorySelection {
  final String path;
  final String? bookmark;

  const DirectorySelection({
    required this.path,
    this.bookmark,
  });
}

/// 安全范围书签会话句柄
class SecurityScopedBookmarkSession {
  final String handle;

  const SecurityScopedBookmarkSession(this.handle);
}

/// macOS 安全范围书签工具
class MacOSSecurityScopedBookmark {
  static const MethodChannel _channel =
      MethodChannel('sftp_sync_manager/macos_bookmarks');

  /// 选择目录并返回包含书签的数据（仅 macOS）
  static Future<DirectorySelection?> pickDirectory({
    String? initialDirectory,
  }) async {
    if (!Platform.isMacOS) {
      return null;
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickDirectory',
      {
        if (initialDirectory != null) 'initialDirectory': initialDirectory,
      },
    );

    if (result == null) {
      return null;
    }

    return DirectorySelection(
      path: result['path'] as String,
      bookmark: result['bookmark'] as String?,
    );
  }

  /// 开始访问安全范围资源
  static Future<SecurityScopedBookmarkSession?> startAccess(
    String? bookmark,
  ) async {
    if (!Platform.isMacOS || bookmark == null || bookmark.isEmpty) {
      return null;
    }

    final handle = await _channel.invokeMethod<String>(
      'startAccess',
      {'bookmark': bookmark},
    );

    if (handle == null) {
      throw PlatformException(
        code: 'BOOKMARK_ACCESS_FAILED',
        message: '无法获取安全范围访问权限',
      );
    }

    return SecurityScopedBookmarkSession(handle);
  }

  /// 结束访问
  static Future<void> stopAccess(
    SecurityScopedBookmarkSession? session,
  ) async {
    if (!Platform.isMacOS || session == null) {
      return;
    }

    await _channel.invokeMethod<void>(
      'stopAccess',
      {'handle': session.handle},
    );
  }
}
