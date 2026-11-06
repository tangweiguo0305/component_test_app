import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleConnectPage extends StatefulWidget {
  const BleConnectPage({super.key});

  @override
  State<BleConnectPage> createState() => _BleConnectPageState();
}

class _BleConnectPageState extends State<BleConnectPage> {
  List<ScanResult> _devices = [];
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  String _connectionStatus = '未连接';

  @override
  void initState() {
    super.initState();
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    // 请求权限
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!statuses.values.every((status) => status.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缺少必要权限')),
        );
      }
      return;
    }

    try {
      await FlutterBluePlus.startScan();

      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() => _devices = results);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _connectionStatus = '正在连接...';
    });

    try {
      await device.connect(
        license: License.free,
        timeout: const Duration(seconds: 10),
        mtu: null,
      );

      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _connectionStatus = '已连接: ${device.platformName}';
          _isConnecting = false;
        });
      }

      // 停止扫描
      await FlutterBluePlus.stopScan();

      // 获取服务
      if (mounted) {
        _getServices(device);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionStatus = '连接失败: $e';
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _getServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发现 ${services.length} 个服务')),
        );
      }

      // 显示服务详情
      if (mounted) {
        _showServicesDialog(services);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取服务失败: $e')),
        );
      }
    }
  }

  void _showServicesDialog(List<BluetoothService> services) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现的服务'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: services.length,
            itemBuilder: (context, index) {
              final service = services[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service: ${service.uuid}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '特征数: ${service.characteristics.length}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (index < services.length - 1)
                    const Divider(height: 16),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectDevice() async {
    if (_connectedDevice == null) return;

    try {
      await _connectedDevice!.disconnect();

      if (mounted) {
        setState(() {
          _connectedDevice = null;
          _connectionStatus = '未连接';
        });
      }

      // 重新扫描
      _scanDevices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('断开连接失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接蓝牙设备'),
      ),
      body: Column(
        children: [
          // 连接状态
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _connectedDevice != null
                ? Colors.green.shade100
                : Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('连接状态', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  _connectionStatus,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _connectedDevice != null
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // 设备列表或已连接提示
          Expanded(
            child: _connectedDevice != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_connected,
                          size: 64,
                          color: Colors.green.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _connectedDevice!.platformName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '设备已连接',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final result = _devices[index];
                      final device = result.device;

                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.platformName.isNotEmpty
                            ? device.platformName
                            : '未命名设备'),
                        subtitle: Text(
                          device.remoteId.toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: ElevatedButton(
                          onPressed: _isConnecting
                              ? null
                              : () => _connectToDevice(device),
                          child: const Text('连接'),
                        ),
                      );
                    },
                  ),
          ),

          // 断开连接按钮
          if (_connectedDevice != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: _disconnectDevice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('断开连接'),
              ),
            ),
        ],
      ),
    );
  }
}
