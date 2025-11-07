import 'package:flutter/material.dart';
import 'screens/task_list_screen.dart';
import 'services/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 WorkManager（仅在支持的平台上）
  try {
    await SchedulerService.initialize();
  } catch (e) {
    // WorkManager 在某些平台上可能不支持，忽略错误继续启动
    debugPrint('WorkManager 初始化失败（可能不支持当前平台）: $e');
  }

  runApp(const SftpSyncApp());
}

class SftpSyncApp extends StatelessWidget {
  const SftpSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SFTP Sync Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TaskListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
