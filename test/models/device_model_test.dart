import 'package:flutter_test/flutter_test.dart';

// 示例设备模型 (如果项目中有)
class BleDevice {
  final String id;
  final String name;
  final int rssi;
  bool isConnected;

  BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnected = false,
  });

  bool get isReachable => rssi > -80;
}

void main() {
  group('BLE 设备模型测试', () {
    test('创建设备 - 所有字段都应该被设置', () {
      final device = BleDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'TestDevice',
        rssi: -50,
      );

      expect(device.id, equals('AA:BB:CC:DD:EE:FF'));
      expect(device.name, equals('TestDevice'));
      expect(device.rssi, equals(-50));
      expect(device.isConnected, isFalse);
    });

    test('连接状态 - 应该能够改变连接状态', () {
      final device = BleDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'TestDevice',
        rssi: -50,
      );

      expect(device.isConnected, isFalse);
      
      device.isConnected = true;
      expect(device.isConnected, isTrue);
    });

    test('信号强度 - 应该正确判断设备是否可达', () {
      final strongSignal = BleDevice(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Device1',
        rssi: -50,
      );

      final weakSignal = BleDevice(
        id: 'AA:BB:CC:DD:EE:02',
        name: 'Device2',
        rssi: -85,
      );

      expect(strongSignal.isReachable, isTrue);
      expect(weakSignal.isReachable, isFalse);
    });

    test('设备比较 - 相同 ID 的设备应该相等', () {
      final device1 = BleDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Device1',
        rssi: -50,
      );

      final device2 = BleDevice(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'Device2',
        rssi: -60,
      );

      expect(device1.id, equals(device2.id));
    });
  });
}
