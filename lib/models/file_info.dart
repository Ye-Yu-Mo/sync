/// 文件信息
class FileInfo {
  /// 相对路径
  final String relativePath;

  /// 文件大小（字节）
  final int size;

  /// 修改时间
  final DateTime modifiedTime;

  const FileInfo({
    required this.relativePath,
    required this.size,
    required this.modifiedTime,
  });

  /// 从 JSON 创建
  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      relativePath: json['relativePath'] as String,
      size: json['size'] as int,
      modifiedTime: DateTime.parse(json['modifiedTime'] as String),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'relativePath': relativePath,
      'size': size,
      'modifiedTime': modifiedTime.toIso8601String(),
    };
  }

  /// 复制并修改部分字段
  FileInfo copyWith({
    String? relativePath,
    int? size,
    DateTime? modifiedTime,
  }) {
    return FileInfo(
      relativePath: relativePath ?? this.relativePath,
      size: size ?? this.size,
      modifiedTime: modifiedTime ?? this.modifiedTime,
    );
  }

  @override
  String toString() {
    return 'FileInfo(path: $relativePath, size: $size, mtime: $modifiedTime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileInfo &&
        other.relativePath == relativePath &&
        other.size == size &&
        other.modifiedTime == modifiedTime;
  }

  @override
  int get hashCode {
    return Object.hash(relativePath, size, modifiedTime);
  }
}
