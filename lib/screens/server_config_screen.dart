import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/services.dart';

/// 服务器配置界面
class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final StorageService _storage = StorageService();

  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _remoteBaseDirController;
  late final TextEditingController _defaultLocalDirController;

  bool _isSaving = false;
  bool _isLoading = true;
  AppConfig? _existingConfig;

  static const _defaultHost = 'sftp.example.com';
  static const _defaultPort = '22';
  static const _defaultUsername = 'syncuser';
  static const _defaultRemoteBase = '/data';

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: _defaultHost);
    _portController = TextEditingController(text: _defaultPort);
    _usernameController = TextEditingController(text: _defaultUsername);
    _passwordController = TextEditingController();
    _remoteBaseDirController = TextEditingController(text: _defaultRemoteBase);
    _defaultLocalDirController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remoteBaseDirController.dispose();
    _defaultLocalDirController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _storage.loadConfig();
      if (config != null) {
        _hostController.text = config.server.host;
        _portController.text = config.server.port.toString();
        _usernameController.text = config.server.username;
        _passwordController.text = config.server.password;
        _remoteBaseDirController.text = config.server.remoteBaseDir;
        _defaultLocalDirController.text = config.server.defaultLocalDir ?? '';
      }
      setState(() {
        _existingConfig = config;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载配置失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器配置'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _isLoading ? null : _saveConfig,
              child: const Text('保存'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTextField(
                    label: '主机地址',
                    controller: _hostController,
                    icon: Icons.dns_outlined,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入主机地址';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: '端口',
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    icon: Icons.numbers,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入端口';
                      }
                      final port = int.tryParse(value);
                      if (port == null || port <= 0 || port > 65535) {
                        return '请输入有效的端口号';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'SSH 用户名',
                    controller: _usernameController,
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入用户名';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'SSH 密码',
                    controller: _passwordController,
                    icon: Icons.lock_outline,
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入密码';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: '远程基础目录（例如 /data/）',
                    controller: _remoteBaseDirController,
                    icon: Icons.folder_shared_outlined,
                    helperText: '应用会在该目录下追加 FileBrowser 用户子目录',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入远程基础目录';
                      }
                      if (!value.startsWith('/')) {
                        return '路径必须以 / 开头';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: '默认本地目录（可选）',
                    controller: _defaultLocalDirController,
                    icon: Icons.folder_outlined,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '提示：服务器配置会被所有同步任务共享。修改后需要重新校验 SSH 凭证。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool obscureText = false,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: icon != null ? Icon(icon) : null,
        helperText: helperText,
      ),
      validator: validator,
    );
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final server = ServerConfig(
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        remoteBaseDir: _remoteBaseDirController.text.trim(),
        defaultLocalDir: _defaultLocalDirController.text.trim().isEmpty
            ? null
            : _defaultLocalDirController.text.trim(),
      );

      final newConfig = _existingConfig != null
          ? _existingConfig!.copyWith(server: server)
          : AppConfig.empty(server: server);

      await _storage.saveConfig(newConfig);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务器配置已保存')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
