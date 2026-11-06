import 'package:flutter/material.dart';
import 'ble_scan_page.dart';
import 'ble_connect_page.dart';
import 'ble_wifi_config_page.dart';

class BleProvisionPage extends StatefulWidget {
  const BleProvisionPage({super.key});

  @override
  State<BleProvisionPage> createState() => _BleProvisionPageState();
}

class _BleProvisionPageState extends State<BleProvisionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('蓝牙配网演示'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Text(
              '欢迎使用蓝牙配网工具',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              '该应用集成了 AI_Frame 的蓝牙配网功能，\n支持设备扫描、蓝牙连接、WiFi 联网等基础功能。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            _buildMenuItem(
              icon: Icons.bluetooth_searching,
              title: '1. 扫描设备',
              description: '扫描附近的蓝牙设备',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BleScanPage()),
              ),
            ),
            const SizedBox(height: 16),
            _buildMenuItem(
              icon: Icons.bluetooth_connected,
              title: '2. 连接设备',
              description: '连接已选择的蓝牙设备',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BleConnectPage()),
              ),
            ),
            const SizedBox(height: 16),
            _buildMenuItem(
              icon: Icons.wifi,
              title: '3. WiFi 配置',
              description: '为设备配置 WiFi 网络',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BleWifiConfigPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
          color: Colors.blue.shade50,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: Colors.blue.shade300),
          ],
        ),
      ),
    );
  }
}
