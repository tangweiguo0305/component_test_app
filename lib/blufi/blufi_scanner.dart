import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE 扫描结果
class BlufiScanDevice {
  final String address; // MAC (Android) / UUID (iOS)
  final String name;
  final int rssi;
  final String? manufacturerDataHex;
  final String? physicsId; // 从厂商数据提取的物理ID（8字节hex = 16字符）
  final String? brandKey; // 从厂商数据提取的品牌标识（2字节ASCII）

  const BlufiScanDevice({
    required this.address,
    required this.name,
    required this.rssi,
    this.manufacturerDataHex,
    this.physicsId,
    this.brandKey,
  });

  @override
  String toString() =>
      'BlufiScanDevice(name=$name, address=$address, physicsId=$physicsId, brandKey=$brandKey)';
}

/// 蓝牙适配器状态
enum BlufiAdapterState { unknown, unavailable, unauthorized, off, on }

/// 纯 Dart BLE 扫描器，基于 flutter_blue_plus
class BlufiScanner {
  BlufiScanner._();
  static final BlufiScanner instance = BlufiScanner._();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  final _deviceController = StreamController<BlufiScanDevice>.broadcast();
  final _adapterController = StreamController<BlufiAdapterState>.broadcast();

  Stream<BlufiScanDevice> get onDevice => _deviceController.stream;
  Stream<BlufiAdapterState> get onAdapterState => _adapterController.stream;

  /// 初始化：监听蓝牙适配器状态
  void init() {
    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      _adapterController.add(_mapAdapterState(state));
    });
  }

  /// 开始扫描
  Future<void> startScan() async {
    await _scanSub?.cancel();
    _scanSub = null;

    // 先停止之前可能残留的扫描
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final device = _parseScanResult(r);
        if (device != null) {
          _deviceController.add(device);
        }
      }
    });

    await FlutterBluePlus.startScan(
      androidScanMode: AndroidScanMode.lowLatency,
      continuousUpdates: true,
    );
  }

  /// 停止扫描
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  /// 获取当前蓝牙适配器状态
  Future<BlufiAdapterState> getAdapterState() async {
    final state = await FlutterBluePlus.adapterState.first;
    return _mapAdapterState(state);
  }

  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _deviceController.close();
    _adapterController.close();
  }

  // ─── 解析扫描结果 ──────────────────────────────────────────────────────────

  BlufiScanDevice? _parseScanResult(ScanResult r) {
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;

    if (name.isEmpty) return null;

    // 获取设备地址
    // Android: MAC 地址；iOS: UUID 字符串
    final address = r.device.remoteId.str;

    // 解析厂商数据
    String? manufacturerDataHex;
    String? physicsId;
    String? brandKey;

    final mfData = r.advertisementData.manufacturerData;
    if (mfData.isNotEmpty) {
      // flutter_blue_plus 返回 Map<int, List<int>>，key 是厂商ID
      final entry = mfData.entries.first;
      final rawBytes = entry.value; // 不含厂商ID的数据部分

      // 构建完整 hex（含厂商ID，与原生行为一致）
      final mfId = entry.key;
      final fullBytes = [
        mfId & 0xff,
        (mfId >> 8) & 0xff,
        ...rawBytes,
      ];
      manufacturerDataHex =
          fullBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // 解析 physicsId 和 brandKey
      // 格式（含厂商ID前缀）：[厂商ID 2字节][physicsId 8字节][brandKey 2字节]
      // 即 fullBytes[2..9] = physicsId，fullBytes[10..11] = brandKey
      if (fullBytes.length >= 10) {
        physicsId = fullBytes
            .sublist(2, 10)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
      }
      if (fullBytes.length >= 12) {
        try {
          brandKey = String.fromCharCodes([fullBytes[10], fullBytes[11]]);
        } catch (_) {}
      }
    }

    return BlufiScanDevice(
      address: address,
      name: name,
      rssi: r.rssi,
      manufacturerDataHex: manufacturerDataHex,
      physicsId: physicsId,
      brandKey: brandKey,
    );
  }

  BlufiAdapterState _mapAdapterState(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return BlufiAdapterState.on;
      case BluetoothAdapterState.off:
        return BlufiAdapterState.off;
      case BluetoothAdapterState.unauthorized:
        return BlufiAdapterState.unauthorized;
      case BluetoothAdapterState.unavailable:
        return BlufiAdapterState.unavailable;
      default:
        return BlufiAdapterState.unknown;
    }
  }
}
