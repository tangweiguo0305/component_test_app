import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:convert';

import 'blufi_callback.dart';
import 'blufi_client.dart';
import 'blufi_configure_params.dart';
import 'blufi_parameter.dart';
import 'blufi_scanner.dart';
import 'blufi_ssid_codec.dart';
import 'response/blufi_scan_result.dart';
import 'response/blufi_status_response.dart';
import 'response/blufi_version_response.dart';

/// BlufiManager — 纯 Dart 实现的 BluFi 适配层
///
/// 对外接口与原 EspBlufi 插件保持一致，内部使用：
/// - [BlufiScanner]：基于 flutter_blue_plus 的 BLE 扫描
/// - [BlufiClient]：纯 Dart 实现的 BluFi GATT 协议
///
/// 消息格式（onMessageReceived 回调）与原插件保持一致，
/// 使用相同的 JSON key，方便 BleManager 无缝切换。
class BlufiManager {
  BlufiManager._();
  static final BlufiManager instance = BlufiManager._();

  // 当前连接的 BlufiClient（单设备架构）
  BlufiClient? _client;
  String? _connectedBleId;
  final Map<String, List<int>> _scannedSsidBytes = {};
  bool _isConnecting = false; // 防止并发连接重入

  // 消息回调（与原插件接口一致）
  void Function(String data)? _successCallback;
  void Function(String data)? _errorCallback;

  // 连接状态订阅
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionStateSub;

  // 扫描结果订阅
  StreamSubscription<BlufiScanDevice>? _scanSub;

  // ─── 初始化回调（替代 EspBlufi.onMessageReceived） ────────────────────────

  void onMessageReceived({
    required void Function(String data) successCallback,
    void Function(String data)? errorCallback,
  }) {
    _successCallback = successCallback;
    _errorCallback = errorCallback;

    // 初始化扫描器，监听蓝牙适配器状态
    BlufiScanner.instance.init();
    BlufiScanner.instance.onAdapterState.listen((state) {
      final stateStr = _mapAdapterState(state);
      _emit('bluetooth_adapter_state', stateStr);
    });

    // 监听扫描结果
    _scanSub?.cancel();
    _scanSub = BlufiScanner.instance.onDevice.listen(_onScanDevice);

    debugPrint('✅ [BlufiManager] 消息回调已注册');
  }

  // ─── 扫描 ─────────────────────────────────────────────────────────────────

  Future<void> scanDeviceInfo({String? filterString}) async {
    try {
      await BlufiScanner.instance.startScan();
      debugPrint('✅ [BlufiManager] 扫描已启动');
    } catch (e) {
      debugPrint('❌ [BlufiManager] 启动扫描失败: $e');
    }
  }

  Future<void> stopScan() async {
    try {
      await BlufiScanner.instance.stopScan();
      debugPrint('✅ [BlufiManager] 扫描已停止');
    } catch (e) {
      debugPrint('❌ [BlufiManager] 停止扫描失败: $e');
    }
  }

  // ─── 连接 ─────────────────────────────────────────────────────────────────

  Future<void> connectPeripheral({
    required String peripheralAddress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // 防止并发连接重入
    if (_isConnecting) {
      debugPrint('⚠️ [BlufiManager] 已有连接进行中，忽略重复请求: $peripheralAddress');
      return;
    }

    // 如果已连接同一设备，直接返回
    if (_connectedBleId == peripheralAddress) {
      debugPrint('ℹ️ [BlufiManager] 设备已连接: $peripheralAddress');
      _emitConnectionState(peripheralAddress, 'connected');
      return;
    }

    _isConnecting = true;
    try {
      debugPrint('🔌 [BlufiManager] 连接设备: $peripheralAddress');

      // 断开之前的连接
      await _disconnectCurrent();

      final device = fbp.BluetoothDevice.fromId(peripheralAddress);

      // 监听连接状态（先取消旧的，再订阅新的）
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        _onConnectionStateChanged(peripheralAddress, state);
      });

      // 发起连接
      await device.connect(
        license: fbp.License.free,
        timeout: timeout,
        mtu: null, // MTU 在 GATT 就绪后手动请求
      );
      debugPrint('✅ [BlufiManager] 连接请求已发送: $peripheralAddress');

      // 连接成功事件会在 _onConnectionStateChanged 中处理
    } catch (e) {
      debugPrint('❌ [BlufiManager] 连接失败: $e');
      _emitConnectionState(peripheralAddress, 'disconnected');
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> requestCloseConnection({String? peripheralAddress}) async {
    try {
      final targetId = peripheralAddress ?? _connectedBleId;
      if (targetId == null) {
        debugPrint('⚠️ [BlufiManager] 无设备可断开');
        return;
      }
      debugPrint('🔌 [BlufiManager] 断开设备: $targetId');

      if (_connectedBleId == targetId) {
        await _disconnectCurrent();
      } else {
        // 断开指定设备（可能不是当前连接的）
        try {
          final device = fbp.BluetoothDevice.fromId(targetId);
          await device.disconnect();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('❌ [BlufiManager] 断开失败: $e');
    }
  }

  // ─── BluFi 协议操作 ───────────────────────────────────────────────────────

  Future<void> requestDeviceVersion() async {
    final client = _client;
    if (client == null) {
      debugPrint('⚠️ [BlufiManager] requestDeviceVersion: 无连接');
      return;
    }
    await client.requestDeviceVersion();
  }

  Future<void> requestDeviceWifiScan({String? peripheralAddress}) async {
    final client = _client;
    if (client == null) {
      debugPrint('⚠️ [BlufiManager] requestDeviceWifiScan: 无连接');
      return;
    }
    await client.requestDeviceWifiScan();
  }

  Future<void> configProvision({
    required String ssid,
    String? bssid,
    String? password,
    String? authData,
  }) async {
    final client = _client;
    if (client == null) {
      debugPrint('⚠️ [BlufiManager] configProvision: 无连接');
      return;
    }

    final originalBytes = BlufiSsidCodec.originalBytesFor(
      _scannedSsidBytes,
      ssid,
      bssid,
    );
    final reencodedBytes = BlufiSsidCodec.encode(ssid);
    final ssidBytes = originalBytes ?? reencodedBytes;
    final encoding = originalBytes == null
        ? 'utf8_fallback'
        : BlufiSsidCodec.decodeScanResult(originalBytes)?.encoding ?? 'unknown';
    final matches = _bytesEqual(ssidBytes, reencodedBytes);
    final ssidHex = ssidBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    debugPrint(
      '[9-16-WIFI测试][RAW-SSID] '
      'source=${originalBytes == null ? 'utf8_fallback' : 'device_scan_raw'} '
      'encoding=$encoding bytes=${ssidBytes.length} '
      'matchesUtf8=$matches hex=[$ssidHex] '
      'bssid=${bssid ?? '<null>'}',
    );
    debugPrint(
      '[BlufiManager][SSID-TRACE] 准备下发: '
      'value=${ssid.replaceAll(' ', '␠')}, '
      'runes=${ssid.runes.length}, bytes=${ssidBytes.length}, '
      'hex=[$ssidHex], bssid=${bssid ?? '<null>'}',
    );

    final params = BlufiConfigureParams()
      ..opMode = kOpModeSta
      ..staSSIDBytes = ssidBytes
      ..staBSSID = bssid
      ..staPassword = password ?? ''
      ..authData = authData;

    await client.configure(params);
  }

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> sendCustomData({required Uint8List data}) async {
    final client = _client;
    if (client == null) {
      debugPrint('⚠️ [BlufiManager] sendCustomData: 无连接');
      return;
    }
    await client.postCustomData(data.toList());
  }

  /// 获取手机当前连接的 WiFi 信息（JSON 字符串）
  /// 返回格式与原插件一致：{"ssid":"xxx","bssid":"xxx","source":"phone"}
  Future<String?> getCurrentWifi() async {
    try {
      if (Platform.isAndroid) {
        final ssid = await WiFiForIoTPlugin.getSSID();
        final bssid = await WiFiForIoTPlugin.getBSSID();

        if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') {
          debugPrint('⚠️ [BlufiManager] 手机未连接WiFi或无权限');
          return null;
        }

        final result = {
          'ssid': ssid,
          'bssid': bssid ?? '',
          'source': 'phone',
        };
        return jsonEncode(result);
      } else if (Platform.isIOS) {
        // iOS 需要 NEHotspotNetwork，wifi_iot 在 iOS 上支持有限
        // 尝试获取，失败则返回 null
        try {
          final ssid = await WiFiForIoTPlugin.getSSID();
          if (ssid == null || ssid.isEmpty) return null;
          final result = {
            'ssid': ssid,
            'bssid': '',
            'source': 'phone',
          };
          return jsonEncode(result);
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ [BlufiManager] getCurrentWifi 失败: $e');
      return null;
    }
  }

  // ─── 内部：连接状态处理 ───────────────────────────────────────────────────

  void _onConnectionStateChanged(
    String bleId,
    fbp.BluetoothConnectionState state,
  ) {
    debugPrint('🔗 [BlufiManager] 连接状态变化: $bleId -> $state');

    if (state == fbp.BluetoothConnectionState.connected) {
      _connectedBleId = bleId;
      // 先初始化 BlufiClient（含安全协商），完成后再通知 BleManager
      _initClient(bleId).then((_) {
        _emitConnectionState(bleId, 'connected');
      });
    } else if (state == fbp.BluetoothConnectionState.disconnected) {
      if (_connectedBleId == bleId) {
        _connectedBleId = null;
        _client = null;
        _scannedSsidBytes.clear();
      }
      _emitConnectionState(bleId, 'disconnected');
    }
  }

  Future<void> _initClient(String bleId) async {
    try {
      _scannedSsidBytes.clear();
      debugPrint('🔧 [BlufiManager] 初始化 BlufiClient: $bleId');

      final device = fbp.BluetoothDevice.fromId(bleId);

      final client = BlufiClient(device);
      client.setCallback(_BlufiCallbackImpl(bleId, this));
      _client = client;

      // 请求更大 MTU（Android），并告知 BlufiClient 避免不必要的分包
      if (Platform.isAndroid) {
        try {
          final mtu = await device.requestMtu(512);
          debugPrint('📏 [BlufiManager] MTU 已设置: $mtu');
          // 与原 esp_blufi_bssid 插件行为一致，固定使用 255 字节包大小
          client.setPostPackageLengthLimit(255);
        } catch (_) {}
      } else if (Platform.isIOS) {
        // iOS 原生插件默认包大小为 128
        client.setPostPackageLengthLimit(128);
      }

      await client.init();
      debugPrint('✅ [BlufiManager] BlufiClient GATT 初始化完成');
      // 不做安全协商，直接明文通信（与原 esp_blufi_bssid 插件行为一致）
    } catch (e) {
      debugPrint('❌ [BlufiManager] BlufiClient 初始化失败: $e');
    }
  }

  Future<void> _disconnectCurrent() async {
    try {
      final bleId = _connectedBleId;
      if (bleId == null) return;

      await _client?.close();
      _client = null;

      _connectionStateSub?.cancel();
      _connectionStateSub = null;
      _connectedBleId = null;

      _emitConnectionState(bleId, 'disconnected');
    } catch (e) {
      debugPrint('⚠️ [BlufiManager] 断开当前连接失败: $e');
    }
  }

  // ─── 内部：扫描结果处理 ───────────────────────────────────────────────────

  void _onScanDevice(BlufiScanDevice device) {
    // 转换为原插件格式的 JSON
    final data = {
      'address': device.address,
      'name': device.name,
      'rssi': device.rssi.toString(),
      'manufacturerData': device.manufacturerDataHex ?? '',
      'physicsId': device.physicsId ?? '',
      'brandKey': device.brandKey ?? '',
    };
    _emit('ble_scan_result', data);
  }

  // ─── 内部：消息发送 ───────────────────────────────────────────────────────

  void _emit(String key, dynamic value) {
    final msg = jsonEncode({'key': key, 'value': value});
    _successCallback?.call(msg);
  }

  void _emitWithAddress(String key, dynamic value, String address) {
    final msg = jsonEncode({'key': key, 'value': value, 'address': address});
    _successCallback?.call(msg);
  }

  void _emitConnectionState(String bleId, String state) {
    final value = jsonEncode({'address': bleId, 'state': state});
    _emit('device_connection_state', value);
  }

  String _mapAdapterState(BlufiAdapterState state) {
    switch (state) {
      case BlufiAdapterState.on:
        return 'on';
      case BlufiAdapterState.off:
        return 'off';
      case BlufiAdapterState.unauthorized:
        return 'unauthorized';
      case BlufiAdapterState.unavailable:
        return 'unsupported';
      default:
        return 'unknown';
    }
  }

  void dispose() {
    _scanSub?.cancel();
    _connectionStateSub?.cancel();
    _client?.close();
    BlufiScanner.instance.dispose();
  }
}

// ─── BlufiCallback 实现 ───────────────────────────────────────────────────────

class _BlufiCallbackImpl extends BlufiCallback {
  final String bleId;
  final BlufiManager manager;

  _BlufiCallbackImpl(this.bleId, this.manager);

  @override
  void onGattPrepared(int status,
      {bool writeCharFound = false, bool notifyCharFound = false}) {
    if (status == blufiStatusSuccess) {
      debugPrint('✅ [BlufiManager] GATT 就绪: bleId=$bleId');
      manager._emitWithAddress('GATT_SUCCESS', '1', bleId);
    } else {
      debugPrint('❌ [BlufiManager] GATT 初始化失败: bleId=$bleId, status=$status');
      manager._emitConnectionState(bleId, 'disconnected');
    }
  }

  @override
  void onNegotiateSecurityResult(int status) {
    // 当前不使用安全协商，此回调不会被触发
    debugPrint('[BlufiManager] onNegotiateSecurityResult: status=$status');
  }

  @override
  void onDeviceVersionResponse(int status, BlufiVersionResponse? response) {
    if (status == blufiStatusSuccess && response != null) {
      final version = '${response.bigVer}.${response.smallVer}';
      debugPrint('📋 [BlufiManager] 设备版本: $version');
      manager._emit('device_version', version);
    } else {
      manager._emit('device_version', '0');
    }
  }

  @override
  void onDeviceStatusResponse(int status, BlufiStatusResponse? response) {
    if (status == blufiStatusSuccess && response != null) {
      final reportedSsid = response.staSSID;
      final reportedSsidBytes =
          reportedSsid == null ? null : BlufiSsidCodec.encode(reportedSsid);
      final reportedSsidHex = reportedSsidBytes
          ?.map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      debugPrint(
        '[BlufiManager][SSID-TRACE] 设备状态回调: '
        'opMode=${response.opMode}, '
        'staConnectionStatus=${response.staConnectionStatus}, '
        'connected=${response.isStaConnected}, '
        'reportedSsid=${reportedSsid?.replaceAll(' ', '␠') ?? '<null>'}, '
        'reportedHex=[${reportedSsidHex ?? ''}]',
      );
      // device_status：通用状态
      final connected = response.isStaConnected ? '1' : '0';
      manager._emit('device_status', connected);
      // device_wifi_connect：配网结果（与原插件 device_wifi_connect 消息一致）
      manager._emit('device_wifi_connect', connected);
    }
  }

  @override
  void onDeviceScanResult(int status, List<BlufiScanResult> results) {
    if (status == blufiStatusSuccess) {
      manager._scannedSsidBytes.clear();
      for (final result in results) {
        final raw = result.rawSsidBytes;
        if (raw == null || result.bssid.isEmpty) continue;
        manager._scannedSsidBytes[
                BlufiSsidCodec.scanKey(result.ssid, result.bssid)] =
            List<int>.from(raw);
      }
      final list = results
          .map((r) => {
                'ssid': r.ssid,
                'rssi': r.rssi.toString(),
                'bssid': r.bssid,
              })
          .toList();
      manager._emitWithAddress('wifi_info', list, bleId);
    }
  }

  @override
  void onPostConfigureParams(int status) {
    // 配网命令发送完成，等待设备连接WiFi结果
    debugPrint('📡 [BlufiManager] 配网命令发送完成, status=$status');
  }

  @override
  void onPostCustomDataResult(int status, List<int> data) {
    manager._emit('post_custom_data', status == blufiStatusSuccess ? '1' : '0');
  }

  @override
  void onReceiveCustomData(int status, List<int> data) {
    if (status == blufiStatusSuccess) {
      manager._emit('receive_device_custom_data', data);
    }
  }

  @override
  void onError(int errCode) {
    debugPrint('❌ [BlufiManager] BluFi 错误码: $errCode');
    manager._errorCallback
        ?.call(jsonEncode({'key': 'error', 'value': errCode}));
  }
}
