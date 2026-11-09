import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'pages/ble_provision_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 尝试初始化 Hive（在生产环境中）
  // 在测试环境中可能失败，但不会阻止应用启动
  try {
    await Hive.initFlutter();
  } catch (e) {
    // Hive 初始化失败，可能在测试环境中
    // 但这不会影响应用的基础功能
    debugPrint('Hive 初始化失败（可能在测试环境中）: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '蓝牙配网测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BleProvisionPage(),
    );
  }
}
