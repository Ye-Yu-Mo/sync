/// 同步结果
class SyncResult {
  /// 上传文件数
  final int uploadedCount;

  /// 删除文件数
  final int deletedCount;

  /// 冲突文件数
  final int conflictCount;

  /// 错误列表
  final List<String> errors;

  /// 耗时
  final Duration elapsed;

  const SyncResult({
    required this.uploadedCount,
    required this.deletedCount,
    required this.conflictCount,
    required this.errors,
    required this.elapsed,
  });

  /// 创建成功结果（无错误）
  factory SyncResult.success({
    required int uploadedCount,
    required int deletedCount,
    required int conflictCount,
    required Duration elapsed,
  }) {
    return SyncResult(
      uploadedCount: uploadedCount,
      deletedCount: deletedCount,
      conflictCount: conflictCount,
      errors: const [],
      elapsed: elapsed,
    );
  }

  /// 创建失败结果
  factory SyncResult.failure({
    required List<String> errors,
    required Duration elapsed,
  }) {
    return SyncResult(
      uploadedCount: 0,
      deletedCount: 0,
      conflictCount: 0,
      errors: errors,
      elapsed: elapsed,
    );
  }

  /// 从 JSON 创建
  factory SyncResult.fromJson(Map<String, dynamic> json) {
    return SyncResult(
      uploadedCount: json['uploadedCount'] as int,
      deletedCount: json['deletedCount'] as int,
      conflictCount: json['conflictCount'] as int,
      errors: (json['errors'] as List<dynamic>).cast<String>(),
      elapsed: Duration(milliseconds: json['elapsedMs'] as int),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'uploadedCount': uploadedCount,
      'deletedCount': deletedCount,
      'conflictCount': conflictCount,
      'errors': errors,
      'elapsedMs': elapsed.inMilliseconds,
    };
  }

  /// 是否成功（无错误）
  bool get isSuccess => errors.isEmpty;

  /// 是否失败（有错误）
  bool get isFailure => errors.isNotEmpty;

  /// 获取摘要信息
  String get summary {
    final parts = <String>[];
    if (uploadedCount > 0) parts.add('上传 $uploadedCount 个文件');
    if (deletedCount > 0) parts.add('删除 $deletedCount 个文件');
    if (conflictCount > 0) parts.add('$conflictCount 个冲突');
    if (errors.isNotEmpty) parts.add('${errors.length} 个错误');

    return parts.isEmpty ? '无变更' : parts.join('，');
  }

  @override
  String toString() {
    return 'SyncResult($summary, 耗时: ${elapsed.inSeconds}s)';
  }
}
