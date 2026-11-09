import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleScanPage extends StatefulWidget {
  const BleScanPage({super.key});

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
  }

  Future<void> _checkBluetoothState() async {
    // 检查蓝牙是否开启
    FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() {
          _statusMessage = state == BluetoothAdapterState.on ? null : '蓝牙未开启';
        });
      }
    });
  }

  Future<void> _requestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!mounted) return;

    if (!allGranted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少必要权限')));
      return;
    }

    _startScan();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    try {
      setState(() {
        _isScanning = true;
        _scanResults = [];
      });

      // flutter_blue_plus 2.1.1 API
      await FlutterBluePlus.startScan();

      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() => _scanResults = results);
        }
      });

      // 10秒后自动停止扫描
      await Future.delayed(const Duration(seconds: 10));
      _stopScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('扫描失败: $e')));
      }
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      if (mounted) {
        setState(() => _isScanning = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('停止扫描失败: $e')));
      }
    }
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描蓝牙设备')),
      body: Column(
        children: [
          // 状态栏
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.orange.shade100,
              child: Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.orange, fontSize: 14),
              ),
            ),

          // 扫描按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _statusMessage != null
                        ? null
                        : _requestPermissions,
                    icon: Icon(_isScanning ? Icons.stop : Icons.search),
                    label: Text(_isScanning ? '扫描中...' : '开始扫描'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 设备列表
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: Text(
                      _isScanning ? '正在扫描设备...' : '未发现设备',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final result = _scanResults[index];
                      final device = result.device;
                      final rssi = result.rssi;

                      return ListTile(
                        leading: Icon(
                          Icons.bluetooth_audio,
                          color: _getRssiColor(rssi),
                        ),
                        title: Text(
                          device.platformName.isNotEmpty
                              ? device.platformName
                              : '未命名设备',
                        ),
                        subtitle: Text(
                          'MAC: ${device.remoteId}\nRSSI: $rssi dBm',
                          style: const TextStyle(fontSize: 12),
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已选择: ${device.platformName}'),
                              ),
                            );
                          },
                          child: const Text('选择'),
                        ),
                      );
                    },
                  ),
          ),

          // 计数显示
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '共找到 ${_scanResults.length} 个设备',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi > -50) return Colors.green;
    if (rssi > -70) return Colors.yellow.shade700;
    return Colors.red;
  }
}
