import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'blufi_callback.dart';
import 'blufi_configure_params.dart';
import 'blufi_frame.dart';
import 'blufi_parameter.dart';
import 'blufi_ssid_codec.dart';
import 'response/blufi_scan_result.dart';
import 'response/blufi_status_response.dart';
import 'response/blufi_version_response.dart';
import 'security/blufi_aes.dart';
import 'security/blufi_crc.dart';
import 'security/blufi_dh.dart';
import 'security/blufi_md5.dart';

class BlufiClient {
  static const String version = '1.0';

  final fbp.BluetoothDevice device;
  BlufiCallback? _callback;

  fbp.BluetoothCharacteristic? _writeChar;
  fbp.BluetoothCharacteristic? _notifyChar;

  StreamSubscription? _notifySubscription;
  StreamSubscription? _connectionSubscription;

  int _sendSequence = -1;
  int _readSequence = -1;

  bool _encrypted = false;
  bool _checksum = false;
  bool _requireAck = false;

  Uint8List? _aesKey;

  BlufiNotifyData? _notifyData;

  int _packageLengthLimit = -1;
  int _blufiMTU = -1;

  /// 外部可在 MTU 变化时调用更新（对应 Java onMtuChanged 里的 mBlufiMTU = mtu - 4）
  void setMTU(int mtu) => _blufiMTU = mtu - 4;

  // ACK 队列
  final _ackQueue = StreamController<int>.broadcast();

  // 设备公钥队列
  final _devicePublicKeyCompleter = Completer<BigInt>();

  BlufiClient(this.device);

  void setCallback(BlufiCallback callback) {
    _callback = callback;
  }

  void setPostPackageLengthLimit(int limit) {
    _packageLengthLimit = limit <= 0 ? -1 : limit.clamp(kMinPackageLength, 512);
  }

  // ─── 初始化：发现服务并订阅通知 ───────────────────────────────────────────

  Future<void> init() async {
    final services = await device.discoverServices();
    fbp.BluetoothService? blufiService;

    // 打印所有服务 UUID，方便调试
    debugPrint('[BlufiClient] 发现 ${services.length} 个服务:');
    for (final s in services) {
      debugPrint('[BlufiClient]   服务 UUID: ${s.uuid}');
    }

    for (final s in services) {
      final uuid = s.uuid.toString().toLowerCase();
      // 支持完整 128-bit UUID、含0000前缀、以及纯短 UUID（ffff）三种格式
      if (uuid == kBlufiServiceUuid ||
          uuid.contains('0000ffff') ||
          uuid == 'ffff') {
        blufiService = s;
        break;
      }
    }

    if (blufiService == null) {
      debugPrint('[BlufiClient] ❌ 未找到 BluFi 服务 (UUID: $kBlufiServiceUuid)');
      _callback?.onGattPrepared(blufiCodeWriteDataFailed,
          writeCharFound: false, notifyCharFound: false);
      return;
    }

    debugPrint(
        '[BlufiClient] ✅ 找到 BluFi 服务，特征数: ${blufiService.characteristics.length}');
    for (final c in blufiService.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      debugPrint('[BlufiClient]   特征 UUID: $uuid');
      // 支持完整 UUID、含0000前缀、以及纯短 UUID 三种格式
      if (uuid == kBlufiWriteCharUuid ||
          uuid.contains('0000ff01') ||
          uuid == 'ff01') _writeChar = c;
      if (uuid == kBlufiNotifyCharUuid ||
          uuid.contains('0000ff02') ||
          uuid == 'ff02') _notifyChar = c;
    }

    if (_writeChar == null || _notifyChar == null) {
      debugPrint(
          '[BlufiClient] ❌ 特征未找到: write=$_writeChar, notify=$_notifyChar');
      _callback?.onGattPrepared(blufiCodeWriteDataFailed,
          writeCharFound: _writeChar != null,
          notifyCharFound: _notifyChar != null);
      return;
    }

    await _notifyChar!.setNotifyValue(true);
    _notifySubscription = _notifyChar!.onValueReceived.listen(_onNotification);

    debugPrint('[BlufiClient] ✅ GATT 初始化完成');
    _callback?.onGattPrepared(blufiStatusSuccess,
        writeCharFound: true, notifyCharFound: true);
  }

  // ─── 关闭 ─────────────────────────────────────────────────────────────────

  Future<void> close() async {
    // 重置序列号，ESP32 BluFi 协议要求每次连接时序列号从 0 开始
    _sendSequence = -1;
    _readSequence = -1;
    await _notifySubscription?.cancel();
    await _connectionSubscription?.cancel();
    await device.disconnect();
  }

  // ─── 安全协商 ─────────────────────────────────────────────────────────────

  Future<void> negotiateSecurity() async {
    try {
      final dh = BlufiDH();
      final posted = await _postNegotiateSecurity(dh);
      if (!posted) {
        _callback?.onNegotiateSecurityResult(blufiCodeNegPostFailed);
        return;
      }

      // 等待设备公钥（超时 10 秒）
      BigInt devicePublicKey;
      try {
        devicePublicKey = await _devicePublicKeyCompleter.future
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        _callback?.onNegotiateSecurityResult(blufiCodeNegErrDevKey);
        return;
      }

      if (devicePublicKey == BigInt.zero) {
        _callback?.onNegotiateSecurityResult(blufiCodeNegErrDevKey);
        return;
      }

      final sharedSecret = dh.generateSharedSecret(devicePublicKey);
      _aesKey = BlufiMD5.getMD5Bytes(sharedSecret);

      final setSec = await _postSetSecurity(
        ctrlEncrypted: false,
        ctrlChecksum: false,
        dataEncrypted: true,
        dataChecksum: true,
      );

      if (setSec) {
        _encrypted = true;
        _checksum = true;
        // 安全协商完成后重置读写序列号
        // ESP32 BluFi 协议：安全协商后，双方序列号都从 0 重新开始
        _sendSequence = -1;
        _readSequence = -1;
        _callback?.onNegotiateSecurityResult(blufiStatusSuccess);
      } else {
        _encrypted = false;
        _checksum = false;
        _callback?.onNegotiateSecurityResult(blufiCodeNegErrSetSecurity);
      }
    } catch (e) {
      debugPrint('negotiateSecurity error: $e');
      _callback?.onNegotiateSecurityResult(blufiCodeNegErrSecurity);
    }
  }

  Future<bool> _postNegotiateSecurity(BlufiDH dh) async {
    final type = _typeValue(PackageType.data, DataSubType.neg);
    final pHex = dh.p.toRadixString(16);
    final gHex = dh.g.toRadixString(16);
    final kHex = dh.publicKeyHex;

    final pBytes = _hexToBytes(pHex);
    final gBytes = _hexToBytes(gHex);
    final kBytes = _hexToBytes(kHex);

    final totalLen = pBytes.length + gBytes.length + kBytes.length + 6;

    // 先发总长度
    final lenData = [
      0x00, // NEG_SECURITY_SET_TOTAL_LENGTH
      (totalLen >> 8) & 0xff,
      totalLen & 0xff,
    ];
    if (!await _post(false, false, _requireAck, type, lenData)) return false;
    await Future.delayed(const Duration(milliseconds: 10));

    // 再发 P/G/K
    final allData = <int>[0x01]; // NEG_SECURITY_SET_ALL_DATA
    allData.addAll(_encodeLV(pBytes));
    allData.addAll(_encodeLV(gBytes));
    allData.addAll(_encodeLV(kBytes));

    return _post(false, false, _requireAck, type, allData);
  }

  List<int> _encodeLV(List<int> bytes) {
    return [
      (bytes.length >> 8) & 0xff,
      bytes.length & 0xff,
      ...bytes,
    ];
  }

  Future<bool> _postSetSecurity({
    required bool ctrlEncrypted,
    required bool ctrlChecksum,
    required bool dataEncrypted,
    required bool dataChecksum,
  }) async {
    final type = _typeValue(PackageType.ctrl, CtrlSubType.setSecMode);
    int data = 0;
    if (dataChecksum) data |= 1;
    if (dataEncrypted) data |= 0x02;
    if (ctrlChecksum) data |= 0x10;
    if (ctrlEncrypted) data |= 0x20;
    return _post(false, true, _requireAck, type, [data]);
  }

  // ─── 请求设备版本 ──────────────────────────────────────────────────────────

  Future<void> requestDeviceVersion() async {
    final type = _typeValue(PackageType.ctrl, CtrlSubType.getVersion);
    final ok = await _post(_encrypted, _checksum, false, type, null);
    if (!ok) _callback?.onDeviceVersionResponse(blufiCodeWriteDataFailed, null);
  }

  // ─── 请求设备状态 ──────────────────────────────────────────────────────────

  Future<void> requestDeviceStatus() async {
    final type = _typeValue(PackageType.ctrl, CtrlSubType.getWifiStatus);
    final ok = await _post(_encrypted, _checksum, false, type, null);
    if (!ok) _callback?.onDeviceStatusResponse(blufiCodeWriteDataFailed, null);
  }

  // ─── 请求设备 Wi-Fi 扫描列表 ───────────────────────────────────────────────

  Future<void> requestDeviceWifiScan() async {
    final type = _typeValue(PackageType.ctrl, CtrlSubType.getWifiList);
    final ok = await _post(_encrypted, _checksum, _requireAck, type, null);
    if (!ok) _callback?.onDeviceScanResult(blufiCodeWriteDataFailed, []);
  }

  // ─── 配网 ─────────────────────────────────────────────────────────────────

  Future<void> configure(BlufiConfigureParams params) async {
    switch (params.opMode) {
      case kOpModeNull:
        if (!await _postDeviceMode(kOpModeNull)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrSetOpmode);
          return;
        }
        _callback?.onPostConfigureParams(blufiStatusSuccess);
        break;

      case kOpModeSta:
        if (!await _postDeviceMode(kOpModeSta)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrSetOpmode);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 20));
        if (!await _postStaWifiInfo(params)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrPostSta);
          return;
        }
        _callback?.onPostConfigureParams(blufiStatusSuccess);
        break;

      case kOpModeSoftAP:
        if (!await _postDeviceMode(kOpModeSoftAP)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrSetOpmode);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 20));
        if (!await _postSoftAPInfo(params)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrPostSoftAP);
          return;
        }
        _callback?.onPostConfigureParams(blufiStatusSuccess);
        break;

      case kOpModeStaSoftAP:
        if (!await _postDeviceMode(kOpModeStaSoftAP)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrSetOpmode);
          return;
        }
        await Future.delayed(const Duration(milliseconds: 20));
        if (!await _postStaWifiInfo(params)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrPostSta);
          return;
        }
        if (!await _postSoftAPInfo(params)) {
          _callback?.onPostConfigureParams(blufiCodeConfErrPostSoftAP);
          return;
        }
        _callback?.onPostConfigureParams(blufiStatusSuccess);
        break;

      default:
        _callback?.onPostConfigureParams(blufiCodeConfInvalidOpmode);
    }
  }

  Future<bool> _postDeviceMode(int mode) async {
    final type = _typeValue(PackageType.ctrl, CtrlSubType.setOpMode);
    // requireAck=false：设备端序列号可能与我们不同步，不等 ACK 避免超时失败
    return _post(_encrypted, _checksum, false, type, [mode]);
  }

  Future<bool> _postStaWifiInfo(BlufiConfigureParams params) async {
    // 1. 先发 authData（如果有），使用分页自定义数据协议
    if (params.authData != null && params.authData!.isNotEmpty) {
      if (!await _sendCustomDataWithPaging(params.authData!.codeUnits.toList()))
        return false;
    }

    // 2. 发送 SSID
    final ssidType = _typeValue(PackageType.data, DataSubType.staWifiSsid);
    final ssidBytes = params.staSSIDBytes ??
        Uint8List.fromList((params.staBSSID ?? '').codeUnits);
    debugPrint(
      '[BlufiClient][SSID-TRACE] 发送 SSID: bytes=${ssidBytes.length}, '
      'encrypted=$_encrypted, checksum=$_checksum, mtu=$_blufiMTU, '
      'packageLimit=$_packageLengthLimit',
    );
    if (!await _post(_encrypted, _checksum, _requireAck, ssidType, ssidBytes)) {
      debugPrint('[BlufiClient][SSID-TRACE] 发送 SSID 失败');
      return false;
    }
    debugPrint('[BlufiClient][SSID-TRACE] 发送 SSID 成功');
    await Future.delayed(const Duration(milliseconds: 10));

    // 3. 发送 BSSID（如果有）
    if (params.staBSSID != null && params.staBSSID!.isNotEmpty) {
      final bssidType = _typeValue(PackageType.data, DataSubType.staWifiBssid);
      final bssidBytes = _convertBssidToBytes(params.staBSSID!);
      if (!await _post(
          _encrypted, _checksum, _requireAck, bssidType, bssidBytes)) {
        debugPrint('[BlufiClient][SSID-TRACE] 发送 BSSID 失败');
        return false;
      }
      debugPrint('[BlufiClient][SSID-TRACE] 发送 BSSID 成功: ${params.staBSSID}');
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // 4. 发送 Password
    final pwdType = _typeValue(PackageType.data, DataSubType.staWifiPassword);
    if (!await _post(_encrypted, _checksum, _requireAck, pwdType,
        (params.staPassword ?? '').codeUnits)) return false;
    await Future.delayed(const Duration(milliseconds: 10));

    // 5. 发送开始配网命令
    final confirmType = _typeValue(PackageType.ctrl, CtrlSubType.connectWifi);
    final connectCommandSent =
        await _post(false, false, _requireAck, confirmType, null);
    debugPrint(
      '[BlufiClient][SSID-TRACE] 发送连接命令: '
      '${connectCommandSent ? '成功' : '失败'}',
    );
    return connectCommandSent;
  }

  /// 将 BSSID 字符串（AA:BB:CC:DD:EE:FF）转为 6 字节
  List<int> _convertBssidToBytes(String bssid) {
    try {
      return bssid.split(':').map((s) => int.parse(s, radix: 16)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _postSoftAPInfo(BlufiConfigureParams params) async {
    if (params.softAPSSID != null && params.softAPSSID!.isNotEmpty) {
      final type = _typeValue(PackageType.data, DataSubType.softAPWifiSsid);
      if (!await _post(_encrypted, _checksum, _requireAck, type,
          params.softAPSSID!.codeUnits)) return false;
      await Future.delayed(const Duration(milliseconds: 10));
    }

    if (params.softAPPassword != null && params.softAPPassword!.isNotEmpty) {
      final type = _typeValue(PackageType.data, DataSubType.softAPWifiPassword);
      if (!await _post(_encrypted, _checksum, _requireAck, type,
          params.softAPPassword!.codeUnits)) return false;
      await Future.delayed(const Duration(milliseconds: 10));
    }

    if (params.softAPChannel > 0) {
      final type = _typeValue(PackageType.data, DataSubType.softAPChannel);
      if (!await _post(
          _encrypted, _checksum, _requireAck, type, [params.softAPChannel]))
        return false;
      await Future.delayed(const Duration(milliseconds: 10));
    }

    if (params.softAPMaxConnection > 0) {
      final type =
          _typeValue(PackageType.data, DataSubType.softAPMaxConnectionCount);
      if (!await _post(_encrypted, _checksum, _requireAck, type,
          [params.softAPMaxConnection])) return false;
      await Future.delayed(const Duration(milliseconds: 10));
    }

    final secType = _typeValue(PackageType.data, DataSubType.softAPAuthMode);
    return _post(
        _encrypted, _checksum, _requireAck, secType, [params.softAPSecurity]);
  }

  // ─── 自定义数据 ────────────────────────────────────────────────────────────

  Future<void> postCustomData(List<int> data) async {
    final type = _typeValue(PackageType.data, DataSubType.customData);
    final ok = await _post(_encrypted, _checksum, _requireAck, type, data);
    final status = ok ? blufiStatusSuccess : blufiCodeWriteDataFailed;
    _callback?.onPostCustomDataResult(status, data);
  }

  /// 分页发送自定义数据（带 CRC16 校验）
  /// 数据格式：总字节数(2) + 页码(1) + 当前页字节数(1) + 数据(N) + CRC16(2)
  Future<void> postCustomDataWithPaging(List<int> data) async {
    final ok = await _sendCustomDataWithPaging(data);
    final status = ok ? blufiStatusSuccess : blufiCodeWriteDataFailed;
    _callback?.onPostCustomDataResult(status, data);
  }

  Future<bool> _sendCustomDataWithPaging(List<int> data) async {
    if (data.isEmpty) return true;

    const pageSize = 128;
    final totalBytes = data.length;
    final totalPages = (totalBytes + pageSize - 1) ~/ pageSize;

    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final pageNum = pageIndex + 1;
      final start = pageIndex * pageSize;
      final currentPageSize =
          (start + pageSize > totalBytes) ? totalBytes - start : pageSize;

      final packet = <int>[
        totalBytes & 0xff,
        (totalBytes >> 8) & 0xff,
        pageNum,
        currentPageSize,
        ...data.sublist(start, start + currentPageSize),
      ];

      final crc16 = _calculateCRC16(packet);
      packet.add(crc16 & 0xff);
      packet.add((crc16 >> 8) & 0xff);

      final type = _typeValue(PackageType.data, DataSubType.customData);
      debugPrint(
          '[9-16-WIFI测试][FRAME] auth_page_start page=$pageNum/$totalPages bytes=$currentPageSize time=${DateTime.now().toIso8601String()}');
      final pageSent =
          await _post(_encrypted, _checksum, _requireAck, type, packet);
      debugPrint(
          '[9-16-WIFI测试][FRAME] auth_page_end page=$pageNum/$totalPages ok=$pageSent time=${DateTime.now().toIso8601String()}');
      if (!pageSent) return false;
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return true;
  }

  /// CRC16 MODBUS 校验
  int _calculateCRC16(List<int> data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc ^= b & 0xff;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  // ─── 请求断开连接 ──────────────────────────────────────────────────────────

  Future<void> requestCloseConnection() async {
    final type = _typeValue(PackageType.ctrl, CtrlSubType.closeConnection);
    await _post(false, false, false, type, null);
  }

  // ─── 底层发包 ──────────────────────────────────────────────────────────────

  Future<bool> _post(
    bool encrypt,
    bool checksum,
    bool requireAck,
    int type,
    List<int>? data,
  ) async {
    if (data == null || data.isEmpty) {
      return _postNonData(encrypt, checksum, requireAck, type);
    }
    return _postContainData(encrypt, checksum, requireAck, type, data);
  }

  Future<bool> _postNonData(
      bool encrypt, bool checksum, bool requireAck, int type) async {
    final seq = _nextSendSequence();
    final bytes =
        _buildPacket(type, encrypt, checksum, requireAck, false, seq, null);
    debugPrint(
        '[9-16-WIFI测试][FRAME] send_start seq=$seq type=${type & 3} subtype=${type >> 2} bytes=0 frag=false time=${DateTime.now().toIso8601String()}');
    final ok = await _gattWrite(bytes);
    debugPrint(
        '[9-16-WIFI测试][FRAME] send_end seq=$seq ok=$ok time=${DateTime.now().toIso8601String()}');
    if (!ok) return false;
    if (requireAck) return _waitAck(seq);
    return true;
  }

  Future<bool> _postContainData(bool encrypt, bool checksum, bool requireAck,
      int type, List<int> data) async {
    final pkgLimit = _packageLengthLimit > 0
        ? _packageLengthLimit
        : (_blufiMTU > 0 ? _blufiMTU : kDefaultPackageLength);
    int postDataLimit = pkgLimit - kPackageHeaderLength - 2;
    if (checksum) postDataLimit -= 2;

    int offset = 0;
    while (offset < data.length) {
      final remaining = data.length - offset;
      final chunkSize = remaining.clamp(0, postDataLimit);
      final chunk = data.sublist(offset, offset + chunkSize);
      offset += chunkSize;

      final frag = offset < data.length;
      final seq = _nextSendSequence();

      List<int> payload;
      if (frag) {
        final totalRemaining = data.length - offset + chunk.length;
        payload = [
          totalRemaining & 0xff,
          (totalRemaining >> 8) & 0xff,
          ...chunk,
        ];
      } else {
        payload = chunk;
      }

      final bytes =
          _buildPacket(type, encrypt, checksum, requireAck, frag, seq, payload);
      debugPrint(
          '[9-16-WIFI测试][FRAME] send_start seq=$seq type=${type & 3} subtype=${type >> 2} bytes=${chunk.length} frag=$frag offset=${offset - chunk.length} time=${DateTime.now().toIso8601String()}');
      final written = await _gattWrite(bytes);
      debugPrint(
          '[9-16-WIFI测试][FRAME] send_end seq=$seq ok=$written time=${DateTime.now().toIso8601String()}');
      if (!written) return false;

      if (frag) {
        if (requireAck && !await _waitAck(seq)) return false;
        await Future.delayed(const Duration(milliseconds: 10));
      } else {
        if (requireAck) return _waitAck(seq);
      }
    }
    return true;
  }

  List<int> _buildPacket(
    int type,
    bool encrypt,
    bool checksum,
    bool requireAck,
    bool frag,
    int seq,
    List<int>? data,
  ) {
    final frameCtrl = FrameCtrl.build(
      encrypted: encrypt,
      checksum: checksum,
      requireAck: requireAck,
      frag: frag,
    );

    final dataLen = data?.length ?? 0;
    final packet = <int>[type, frameCtrl, seq, dataLen];

    List<int>? checksumBytes;
    if (checksum) {
      int crc = BlufiCRC.calcCRC(0, [seq, dataLen]);
      if (data != null && data.isNotEmpty) {
        crc = BlufiCRC.calcCRC(crc, data);
      }
      checksumBytes = [crc & 0xff, (crc >> 8) & 0xff];
    }

    // 先算 checksum（基于明文），再加密（与 Java 版一致）
    List<int> payload = data ?? [];
    if (encrypt && _aesKey != null && payload.isNotEmpty) {
      final aes = BlufiAES(_aesKey!, _generateAESIV(seq));
      payload = aes.encrypt(payload);
    }

    packet.addAll(payload);
    if (checksumBytes != null) packet.addAll(checksumBytes);

    return packet;
  }

  Future<bool> _gattWrite(List<int> data) async {
    if (_writeChar == null) return false;
    try {
      // 发包内容可能包含 Wi-Fi 密码或认证数据，禁止打印原始字节。
      debugPrint('[BlufiClient] gattWrite(${data.length}B)');
      await _writeChar!.write(data, withoutResponse: false);
      return true;
    } catch (e) {
      debugPrint('gattWrite error: $e');
      return false;
    }
  }

  Future<bool> _waitAck(int expectSeq) async {
    try {
      final ack = await _ackQueue.stream
          .firstWhere((v) => v == expectSeq)
          .timeout(const Duration(milliseconds: 5000));
      return ack == expectSeq;
    } catch (_) {
      return false;
    }
  }

  // ─── 通知解析 ──────────────────────────────────────────────────────────────

  void _onNotification(List<int> response) {
    // 在长度校验、校验和验证及解析前记录特征通知的原始字节，
    // 用于区分“设备未通知”和“通知到达但后续解析失败”。
    debugPrint(
      '[BLUFI_INIT_EVENT][RAW_NOTIFICATION] '
      'totalLen=${response.length} (payload hidden)',
    );

    if (response.length < 4) {
      debugPrint('[BlufiClient] ⚠️ 收到过短的通知包: ${response.length} 字节');
      _callback?.onError(blufiCodeInvalidNotification);
      return;
    }

    final seq = response[2] & 0xff;
    final type = response[0] & 0xff;
    final frameCtrl = FrameCtrl(response[1] & 0xff);
    final dataLen = response[3] & 0xff;
    final pkgType = type & 0x03;
    final subType = (type >> 2) & 0x3f;

    _readSequence = (_readSequence + 1) & 0xff;
    if (seq != _readSequence) {
      debugPrint(
          'BluFi: sequence mismatch, expected $_readSequence got $seq, resyncing');
      _readSequence = seq;
    }

    debugPrint('[BlufiClient] 收到通知: seq=$seq pkgType=$pkgType subType=$subType '
        'dataLen=$dataLen encrypted=${frameCtrl.isEncrypted} checksum=${frameCtrl.isChecksum} '
        'frag=${frameCtrl.hasFrag} totalLen=${response.length}');

    if (_notifyData == null) _notifyData = BlufiNotifyData();
    _notifyData!.type = type;
    _notifyData!.pkgType = type & 0x03;
    _notifyData!.subType = (type >> 2) & 0x3f;
    _notifyData!.frameCtrl = response[1] & 0xff;
    _notifyData!.type = type;
    _notifyData!.pkgType = type & 0x03;
    _notifyData!.subType = (type >> 2) & 0x3f;
    _notifyData!.frameCtrl = response[1] & 0xff;

    var dataBytes =
        response.sublist(4, 4 + dataLen.clamp(0, response.length - 4));

    // checksum 验证必须在解密之前，基于密文计算（与 Java 版一致）
    if (frameCtrl.isChecksum && response.length >= 4 + dataLen + 2) {
      final respCs1 = response[response.length - 1] & 0xff;
      final respCs2 = response[response.length - 2] & 0xff;
      int crc = BlufiCRC.calcCRC(0, [seq, dataLen]);
      crc = BlufiCRC.calcCRC(crc, dataBytes); // 基于密文
      final calcCs1 = (crc >> 8) & 0xff;
      final calcCs2 = crc & 0xff;
      if (calcCs1 != respCs1 || calcCs2 != respCs2) {
        debugPrint('BluFi: checksum mismatch');
        debugPrint('  raw payload hidden');
        debugPrint(
            '  seq=$seq dataLen=$dataLen encrypted=${frameCtrl.isEncrypted} checksum=${frameCtrl.isChecksum}');
        debugPrint('  dataBytes length: ${dataBytes.length}');
        debugPrint(
            '  expected cs: ${respCs2.toRadixString(16).padLeft(2, '0')} ${respCs1.toRadixString(16).padLeft(2, '0')}');
        debugPrint(
            '  calc cs:     ${calcCs2.toRadixString(16).padLeft(2, '0')} ${calcCs1.toRadixString(16).padLeft(2, '0')}');
        _callback?.onError(blufiCodeInvalidNotification);
        return;
      }
    }

    if (frameCtrl.isEncrypted && _aesKey != null) {
      final aes = BlufiAES(_aesKey!, _generateAESIV(seq));
      dataBytes = aes.decrypt(dataBytes);
      debugPrint('[BlufiClient] 解密后 dataBytes length: ${dataBytes.length}');
    }

    final dataOffset = frameCtrl.hasFrag ? 2 : 0;
    _notifyData!.addData(dataBytes, dataOffset);

    if (!frameCtrl.hasFrag) {
      debugPrint(
          '[BlufiClient] 完整包解析: pkgType=$pkgType subType=$subType dataLen=${_notifyData!.dataBytes.length}');
      _parseBlufiNotifyData(_notifyData!);
      _notifyData = null;
    }
  }

  void _parseBlufiNotifyData(BlufiNotifyData data) {
    final pkgType = data.pkgType;
    final subType = data.subType;
    final bytes = data.dataBytes;

    if (_callback?.onGattNotification(pkgType, subType, bytes) == true) return;

    if (pkgType == PackageType.ctrl) {
      if (subType == CtrlSubType.ack) _parseAck(bytes);
    } else if (pkgType == PackageType.data) {
      switch (subType) {
        case DataSubType.neg:
          _onReceiveDevicePublicKey(bytes);
          break;
        case DataSubType.version:
          _parseVersion(bytes);
          break;
        case DataSubType.wifiConnectionState:
          _parseWifiState(bytes);
          break;
        case DataSubType.wifiList:
          _parseWifiScanList(bytes);
          break;
        case DataSubType.customData:
          _callback?.onReceiveCustomData(blufiStatusSuccess, bytes.toList());
          break;
        case DataSubType.error:
          final errCode = bytes.isNotEmpty ? bytes[0] & 0xff : 0xff;
          debugPrint(
              '[9-16-WIFI测试][DEVICE-ERROR] code=$errCode raw=[${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}] time=${DateTime.now().toIso8601String()}');
          _callback?.onError(errCode);
          break;
      }
    }
  }

  void _parseAck(List<int> data) {
    final ack = data.isNotEmpty ? data[0] & 0xff : 0x100;
    _ackQueue.add(ack);
  }

  void _onReceiveDevicePublicKey(List<int> data) {
    final hex = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    try {
      final key = BigInt.parse(hex, radix: 16);
      if (!_devicePublicKeyCompleter.isCompleted) {
        _devicePublicKeyCompleter.complete(key);
      }
    } catch (_) {
      if (!_devicePublicKeyCompleter.isCompleted) {
        _devicePublicKeyCompleter.complete(BigInt.zero);
      }
    }
  }

  void _parseVersion(List<int> data) {
    if (data.length != 2) {
      _callback?.onDeviceVersionResponse(blufiCodeInvalidData, null);
      return;
    }
    _callback?.onDeviceVersionResponse(
      blufiStatusSuccess,
      BlufiVersionResponse(data[0] & 0xff, data[1] & 0xff),
    );
  }

  void _parseWifiState(List<int> data) {
    if (data.length < 3) {
      _callback?.onDeviceStatusResponse(blufiCodeInvalidData, null);
      return;
    }

    final response = BlufiStatusResponse();
    int i = 0;
    response.opMode = data[i++] & 0xff;
    response.staConnectionStatus = data[i++] & 0xff;
    response.softAPConnCount = data[i++] & 0xff;

    int status = blufiStatusSuccess;
    while (i < data.length) {
      final infoType = data[i++] & 0xff;
      if (i >= data.length) break;
      final len = data[i++] & 0xff;
      if (i + len > data.length) {
        status = blufiCodeInvalidData;
        break;
      }
      final stateBytes = data.sublist(i, i + len);
      i += len;
      _parseWifiStateData(response, infoType, stateBytes);
    }

    _callback?.onDeviceStatusResponse(status, response);
  }

  void _parseWifiStateData(
      BlufiStatusResponse response, int infoType, List<int> data) {
    switch (infoType) {
      case DataSubType.staWifiBssid:
        response.staBSSID =
            data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        break;
      case DataSubType.staWifiSsid:
        response.staSSID = String.fromCharCodes(data);
        break;
      case DataSubType.staWifiPassword:
        response.staPassword = String.fromCharCodes(data);
        break;
      case DataSubType.softAPAuthMode:
        response.softAPSecurity = data[0] & 0xff;
        break;
      case DataSubType.softAPChannel:
        response.softAPChannel = data[0] & 0xff;
        break;
      case DataSubType.softAPMaxConnectionCount:
        response.softAPMaxConnCount = data[0] & 0xff;
        break;
      case DataSubType.softAPWifiPassword:
        response.softAPPassword = String.fromCharCodes(data);
        break;
      case DataSubType.softAPWifiSsid:
        response.softAPSSID = String.fromCharCodes(data);
        break;
    }
  }

  void _parseWifiScanList(List<int> data) {
    final results = <BlufiScanResult>[];
    int i = 0;
    while (i < data.length) {
      final entryStart = i;
      final length = data[i] & 0xff;
      final entryEnd = entryStart + 1 + length;

      // length = RSSI(1B) + SSID(0~32B) + BSSID(6B)
      if (length < 7 || length > 39) {
        debugPrint('[BlufiClient] ⚠️ 跳过异常 WiFi 数据长度: $length');
        // 长度字段仍然完整时跳过整条记录，避免将 SSID 内的字节误认为新记录。
        if (entryEnd <= data.length) {
          i = entryEnd;
          continue;
        }
        break;
      }
      if (entryEnd > data.length) {
        debugPrint(
          '[BlufiClient] ⚠️ WiFi 扫描数据不完整: '
          'remaining=${data.length - entryStart}, required=${length + 1}',
        );
        break;
      }

      final rssi = data[entryStart + 1].toSigned(8);
      final ssidStart = entryStart + 2;
      final ssidLength = length - 7;
      final ssidBytes = data.sublist(ssidStart, ssidStart + ssidLength);
      final decoded = BlufiSsidCodec.decodeScanResult(ssidBytes);
      final bssidStart = ssidStart + ssidLength;
      final bssid = data
          .sublist(bssidStart, bssidStart + 6)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
      i = entryEnd;

      if (decoded == null) {
        final rawHex =
            ssidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        debugPrint('[BlufiClient] ⚠️ 过滤无效或乱码 SSID: [$rawHex]');
        continue;
      }

      final ssid = decoded.value;

      final ssidHex = ssidBytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      debugPrint(
        '[BlufiClient][SSID-TRACE] 扫描结果: '
        'value=${ssid.replaceAll(' ', '␠')}, encoding=${decoded.encoding}, '
        'runes=${ssid.runes.length}, bytes=${ssidBytes.length}, '
        'hex=[$ssidHex], bssid=$bssid, rssi=$rssi',
      );

      results.add(BlufiScanResult(
          type: BlufiScanResult.typeWifi,
          ssid: ssid,
          rssi: rssi,
          bssid: bssid,
          rawSsidBytes: List<int>.unmodifiable(ssidBytes)));
    }
    _callback?.onDeviceScanResult(blufiStatusSuccess, results);
  }

  // ─── 工具方法 ──────────────────────────────────────────────────────────────

  int _typeValue(int pkgType, int subType) => (subType << 2) | pkgType;

  int _nextSendSequence() {
    _sendSequence = (_sendSequence + 1) & 0xff;
    return _sendSequence;
  }

  List<int> _generateAESIV(int sequence) {
    final iv = List<int>.filled(16, 0);
    iv[0] = sequence;
    return iv;
  }

  List<int> _hexToBytes(String hex) {
    if (hex.length % 2 != 0) hex = '0$hex';
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
