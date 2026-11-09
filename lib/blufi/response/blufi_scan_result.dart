class BlufiScanResult {
  static const int typeWifi = 0x01;

  final int type;
  final String ssid;
  final int rssi;
  final String bssid;

  /// 设备扫描包中的 SSID 原始字节，仅用于精确匹配后的配网下发。
  final List<int>? rawSsidBytes;

  const BlufiScanResult({
    required this.type,
    required this.ssid,
    required this.rssi,
    this.bssid = '',
    this.rawSsidBytes,
  });

  @override
  String toString() => 'ssid: $ssid, rssi: $rssi, bssid: $bssid';
}
