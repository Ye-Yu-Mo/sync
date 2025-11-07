import 'file_info.dart';

/// 文件变更（扫描结果）
class FileChanges {
  /// 需要上传的文件（新增或修改）
  final List<FileInfo> toUpload;

  /// 需要删除的文件（待用户确认）
  final List<FileInfo> toDelete;

  /// 冲突文件（需要重命名）
  final List<FileInfo> conflicts;

  const FileChanges({
    required this.toUpload,
    required this.toDelete,
    required this.conflicts,
  });

  /// 创建空的变更集
  factory FileChanges.empty() {
    return const FileChanges(
      toUpload: [],
      toDelete: [],
      conflicts: [],
    );
  }

  /// 从 JSON 创建
  factory FileChanges.fromJson(Map<String, dynamic> json) {
    return FileChanges(
      toUpload: (json['toUpload'] as List<dynamic>)
          .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      toDelete: (json['toDelete'] as List<dynamic>)
          .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      conflicts: (json['conflicts'] as List<dynamic>)
          .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'toUpload': toUpload.map((e) => e.toJson()).toList(),
      'toDelete': toDelete.map((e) => e.toJson()).toList(),
      'conflicts': conflicts.map((e) => e.toJson()).toList(),
    };
  }

  /// 是否有任何变更
  bool get hasChanges {
    return toUpload.isNotEmpty || toDelete.isNotEmpty || conflicts.isNotEmpty;
  }

  /// 总文件数
  int get totalCount {
    return toUpload.length + toDelete.length + conflicts.length;
  }

  @override
  String toString() {
    return 'FileChanges(upload: ${toUpload.length}, delete: ${toDelete.length}, conflicts: ${conflicts.length})';
  }
}
