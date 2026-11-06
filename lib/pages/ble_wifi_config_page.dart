import 'package:flutter/material.dart';
import 'dart:async';
import 'package:component_test_app/blufi/blufi_manager.dart';

class BleWifiConfigPage extends StatefulWidget {
  final String? deviceId;

  const BleWifiConfigPage({
    super.key,
    this.deviceId,
  });

  @override
  State<BleWifiConfigPage> createState() => _BleWifiConfigPageState();
}

class _BleWifiConfigPageState extends State<BleWifiConfigPage> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isObscurePassword = true;
  bool _isConfiguring = false;
  String? _configStatus;

  final BlufiManager _blufiManager = BlufiManager.instance;
  Completer<bool>? _configCompleter; // ← 添加 Completer 用于异步等待

  final List<String> _mockWifiNetworks = [
    'Home_WiFi',
    'Office_Network',
    'Guest_WiFi',
    'Smart_Home',
  ];

  @override
  void initState() {
    super.initState();
    _initBlufiCallbacks();
  }

  /// 初始化 BluFi 回调
  void _initBlufiCallbacks() {
    _blufiManager.onMessageReceived(
      successCallback: (data) {
        debugPrint('✅ BluFi 成功: $data');
        
        // 通知等待者配置成功
        if (_configCompleter != null && !_configCompleter!.isCompleted) {
          _configCompleter!.complete(true);
        }

        if (mounted) {
          setState(() {
            _isConfiguring = false;
            _configStatus = '✓ WiFi 配置成功！设备正在连接网络...';
          });

          Future.delayed(const Duration(seconds: 3)).then((_) {
            if (mounted) {
              setState(() => _configStatus = null);
            }
          });
        }
      },
      errorCallback: (error) {
        debugPrint('❌ BluFi 失败: $error');
        
        // 通知等待者配置失败
        if (_configCompleter != null && !_configCompleter!.isCompleted) {
          _configCompleter!.complete(false);
        }

        if (mounted) {
          setState(() {
            _isConfiguring = false;
            _configStatus = '✗ 配置失败: $error';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi 配置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 配置状态提示
            if (_configStatus != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _configStatus!.contains('成功')
                      ? Colors.green.shade100
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _configStatus!.contains('成功')
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
                child: Text(
                  _configStatus!,
                  style: TextStyle(
                    color: _configStatus!.contains('成功')
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ),

            // 标题
            const Text(
              '选择或输入 WiFi 网络',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // WiFi 网络列表
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _mockWifiNetworks.length,
                separatorBuilder: (_, __) => Divider(
                  height: 0,
                  color: Colors.grey.shade200,
                ),
                itemBuilder: (context, index) {
                  final network = _mockWifiNetworks[index];
                  return ListTile(
                    leading: const Icon(Icons.wifi),
                    title: Text(network),
                    trailing: Radio<String>(
                      value: network,
                      groupValue: _ssidController.text,
                      onChanged: (value) {
                        setState(() => _ssidController.text = value ?? '');
                      },
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // SSID 输入框
            const Text(
              '网络名称 (SSID)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                hintText: '输入 WiFi 网络名称',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.wifi),
              ),
            ),

            const SizedBox(height: 16),

            // 密码输入框
            const Text(
              '网络密码',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: _isObscurePassword,
              decoration: InputDecoration(
                hintText: '输入 WiFi 密码',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isObscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(
                      () => _isObscurePassword = !_isObscurePassword,
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 配置按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConfiguring ? null : _configureWiFi,
                icon: Icon(
                  _isConfiguring
                      ? Icons.hourglass_bottom
                      : Icons.cloud_upload,
                ),
                label: Text(
                  _isConfiguring ? '配置中...' : '开始配置',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 配置说明
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '配置步骤:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildStep('1', '确保设备通过蓝牙已连接'),
                  _buildStep('2', '选择或输入目标 WiFi 网络'),
                  _buildStep('3', '输入 WiFi 密码'),
                  _buildStep('4', '点击开始配置'),
                  _buildStep('5', '等待配置完成'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Future<void> _configureWiFi() async {
    if (_ssidController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 WiFi 网络名称')),
      );
      return;
    }

    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 WiFi 密码')),
      );
      return;
    }

    if (_passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi 密码至少 8 个字符')),
      );
      return;
    }

    setState(() {
      _isConfiguring = true;
      _configStatus = '正在配置 WiFi...';
    });

    try {
      debugPrint('🔌 开始 BluFi 配置: SSID=${_ssidController.text}');

      // 创建 Completer 用于等待设备响应
      _configCompleter = Completer<bool>();

      // 调用真实 BluFi 配置
      await _blufiManager.configProvision(
        ssid: _ssidController.text.trim(),
        password: _passwordController.text,
      );

      debugPrint(
          '✅ BluFi 配置命令已发送给设备，正在等待设备响应...');

      // 等待设备回调响应（最多 5 秒）
      final success = await _configCompleter!.future
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⏱ 等待设备响应超时（5秒）');
              return false; // 超时判定为失败
            },
          )
          .catchError((e) {
            debugPrint('❌ 等待回调异常: $e');
            return false;
          });

      if (mounted && !success) {
        // 未收到成功回调 → 显示超时提示
        setState(() {
          _isConfiguring = false;
          _configStatus =
              '⏱ 等待设备响应超时。命令已发送，请检查设备状态';
        });
      }
    } catch (e) {
      debugPrint('❌ BluFi 配置异常: $e');
      if (mounted) {
        setState(() {
          _isConfiguring = false;
          _configStatus = '✗ 配置异常: $e';
        });
      }
    } finally {
      _configCompleter = null;
    }
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
