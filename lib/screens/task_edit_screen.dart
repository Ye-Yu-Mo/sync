import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../services/services.dart';

/// 任务编辑界面
class TaskEditScreen extends StatefulWidget {
  final SyncTask? task; // null表示新建任务

  const TaskEditScreen({super.key, this.task});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final StorageService _storage = StorageService();
  late final TaskManager _taskManager;

  // 表单控制器
  late final TextEditingController _nameController;
  late final TextEditingController _localDirController;
  late final TextEditingController _remoteDirController;
  late final TextEditingController _intervalController;

  String _fileBrowserUser = 'yachen'; // 默认值
  bool _enabled = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _taskManager = TaskManager(_storage);

    // 初始化控制器
    final task = widget.task;
    _nameController = TextEditingController(text: task?.name ?? '');
    _localDirController = TextEditingController(text: task?.localDir ?? '');
    _remoteDirController = TextEditingController(text: task?.remoteDir ?? '/');
    _intervalController = TextEditingController(
      text: task?.intervalMinutes.toString() ?? '30',
    );
    _fileBrowserUser = task?.fileBrowserUser ?? 'yachen';
    _enabled = task?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _localDirController.dispose();
    _remoteDirController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.task != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑任务' : '新建任务'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveTask,
              child: const Text('保存'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 任务名称
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '任务名称',
                hintText: '例如：工作文档同步',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: _validateTaskName,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // 本地目录
            TextFormField(
              controller: _localDirController,
              decoration: InputDecoration(
                labelText: '本地目录',
                hintText: '选择要同步的本地文件夹',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.folder_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickLocalDirectory,
                  tooltip: '浏览',
                ),
              ),
              validator: _validateLocalDir,
              readOnly: true,
              onTap: _pickLocalDirectory,
            ),

            const SizedBox(height: 16),

            // 远程目录
            TextFormField(
              controller: _remoteDirController,
              decoration: const InputDecoration(
                labelText: '远程目录',
                hintText: '例如：/backup/documents',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cloud_outlined),
                helperText: '服务器上的目标路径（相对于SFTP根目录）',
              ),
              validator: _validateRemoteDir,
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // FileBrowser 用户选择
            DropdownButtonFormField<String>(
              initialValue: _fileBrowserUser,
              decoration: const InputDecoration(
                labelText: 'FileBrowser 用户',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
                helperText: '选择要同步到哪个用户的云盘目录',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'yachen',
                  child: Text('yachen (/data/yachen)'),
                ),
                DropdownMenuItem(
                  value: 'xulei',
                  child: Text('xulei (/data/xulei)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _fileBrowserUser = value;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // 同步间隔
            TextFormField(
              controller: _intervalController,
              decoration: const InputDecoration(
                labelText: '同步间隔（分钟）',
                hintText: '例如：30',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.schedule),
                suffixText: '分钟',
                helperText: '自动同步的时间间隔（最小1分钟）',
              ),
              keyboardType: TextInputType.number,
              validator: _validateInterval,
              textInputAction: TextInputAction.done,
            ),

            const SizedBox(height: 24),

            // 启用开关
            SwitchListTile(
              title: const Text('启用任务'),
              subtitle: const Text('启用后将按设定的间隔自动同步'),
              value: _enabled,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
              secondary: const Icon(Icons.power_settings_new),
            ),

            const SizedBox(height: 24),

            // 信息卡片
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '同步说明',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '• 同步模式：单向推送（本地 → 远程）\n'
                      '• 新增/修改：自动上传到服务器\n'
                      '• 删除文件：需要确认后才会同步\n'
                      '• 冲突处理：服务器文件将被备份\n'
                      '• 后台同步：需要保持应用运行',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 验证任务名称
  String? _validateTaskName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入任务名称';
    }
    if (value.trim().length < 2) {
      return '任务名称至少需要2个字符';
    }
    if (value.trim().length > 50) {
      return '任务名称不能超过50个字符';
    }
    return null;
  }

  /// 验证本地目录
  String? _validateLocalDir(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请选择本地目录';
    }
    // 基本路径格式检查
    if (value.contains('\\\\') || value.contains('//')) {
      return '目录路径格式不正确';
    }
    return null;
  }

  /// 验证远程目录
  String? _validateRemoteDir(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入远程目录';
    }
    final trimmed = value.trim();
    if (!trimmed.startsWith('/')) {
      return '远程目录必须以 / 开头';
    }
    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return '远程目录不能以 / 结尾（根目录除外）';
    }
    if (trimmed.contains('//')) {
      return '远程目录路径不能包含连续的 /';
    }
    return null;
  }

  /// 验证同步间隔
  String? _validateInterval(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入同步间隔';
    }
    final interval = int.tryParse(value.trim());
    if (interval == null) {
      return '请输入有效的数字';
    }
    if (interval < 1) {
      return '同步间隔不能少于1分钟';
    }
    if (interval > 1440) {
      return '同步间隔不能超过1440分钟（24小时）';
    }
    return null;
  }

  /// 选择本地目录
  Future<void> _pickLocalDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择本地同步目录',
        initialDirectory: _localDirController.text.isNotEmpty
            ? _localDirController.text
            : null,
      );

      if (result != null && mounted) {
        setState(() {
          _localDirController.text = result;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择目录失败: $e')),
        );
      }
    }
  }

  /// 保存任务
  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final name = _nameController.text.trim();
      final localDir = _localDirController.text.trim();
      final remoteDir = _remoteDirController.text.trim();
      final intervalMinutes = int.parse(_intervalController.text.trim());

      if (widget.task == null) {
        // 新建任务
        await _taskManager.createTask(
          name: name,
          localDir: localDir,
          remoteDir: remoteDir,
          fileBrowserUser: _fileBrowserUser,
          intervalMinutes: intervalMinutes,
          enabled: _enabled,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('任务"$name"创建成功')),
          );
        }
      } else {
        // 更新任务
        final updatedTask = widget.task!.copyWith(
          name: name,
          localDir: localDir,
          remoteDir: remoteDir,
          fileBrowserUser: _fileBrowserUser,
          intervalMinutes: intervalMinutes,
          enabled: _enabled,
        );

        await _taskManager.updateTask(widget.task!.id, updatedTask);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('任务"$name"更新成功')),
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true); // 返回 true 表示已保存
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
