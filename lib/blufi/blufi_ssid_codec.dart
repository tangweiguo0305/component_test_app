import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;

/// BLUFI SSID 编解码工具。
///
/// Wi-Fi SSID 最长为 32 字节。显示优先使用 UTF-8，仅对明确可还原的
/// GBK 中文名称尝试兼容；下发始终以扫描原始字节为准。
class BlufiSsidCodec {
  BlufiSsidCodec._();

  static const int maxByteLength = 32;

  static String? decodeForDisplay(List<int> bytes) {
    return decodeScanResult(bytes)?.value;
  }

  static ({String value, String encoding})? decodeScanResult(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxByteLength) return null;

    try {
      final ssid = utf8.decode(bytes, allowMalformed: false);
      return _isDisplayable(ssid) ? (value: ssid, encoding: 'utf8') : null;
    } on FormatException {
      // 仅在 UTF-8 字节不合法时尝试 GBK。
    }

    try {
      final ssid = charset.gbk.decode(bytes, allowMalformed: false);
      // GBK 兼容只自动接纳中文候选；不能把任意损坏字节都当作 GBK。
      if (!_isDisplayable(ssid) || !_containsHan(ssid)) return null;
      final reencoded = charset.gbk.encode(ssid);
      if (!_bytesEqual(reencoded, bytes)) return null;
      return (value: ssid, encoding: 'gbk');
    } on FormatException {
      return null;
    }
  }

  static bool _isDisplayable(String ssid) {
    if (ssid.isEmpty || ssid.contains('\uFFFD')) return false;
    var hasVisibleCharacter = false;
    for (final rune in ssid.runes) {
      if (_isControlCharacter(rune)) return false;
      if (!_isWhitespace(rune)) hasVisibleCharacter = true;
    }
    return hasVisibleCharacter;
  }

  static bool _containsHan(String ssid) => ssid.runes.any(
        (rune) =>
            (rune >= 0x3400 && rune <= 0x4dbf) ||
            (rune >= 0x4e00 && rune <= 0x9fff),
      );

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static Uint8List encode(String ssid) {
    return Uint8List.fromList(utf8.encode(ssid));
  }

  /// 只按完整 SSID 与 BSSID 精确匹配原始字节，避免误用其他热点的扫描结果。
  static String scanKey(String ssid, String bssid) =>
      '${bssid.toUpperCase()}|$ssid';

  static Uint8List? originalBytesFor(
    Map<String, List<int>> scanBytes,
    String ssid,
    String? bssid,
  ) {
    if (bssid == null || bssid.isEmpty) return null;
    final bytes = scanBytes[scanKey(ssid, bssid)];
    if (bytes == null || decodeForDisplay(bytes) != ssid) return null;
    return Uint8List.fromList(bytes);
  }

  static bool _isControlCharacter(int rune) {
    return rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f);
  }

  static bool _isWhitespace(int rune) {
    return rune == 0x20 ||
        rune == 0x00a0 ||
        rune == 0x1680 ||
        (rune >= 0x2000 && rune <= 0x200a) ||
        rune == 0x2028 ||
        rune == 0x2029 ||
        rune == 0x202f ||
        rune == 0x205f ||
        rune == 0x3000;
  }
}
