import '../blufi_parameter.dart';

class BlufiStatusResponse {
  int opMode = -1;

  int softAPSecurity = -1;
  int softAPConnCount = -1;
  int softAPMaxConnCount = -1;
  int softAPChannel = -1;
  String? softAPPassword;
  String? softAPSSID;

  int staConnectionStatus = -1;
  String? staBSSID;
  String? staSSID;
  String? staPassword;

  bool get isStaConnected => staConnectionStatus == 0;

  String generateValidInfo() {
    final sb = StringBuffer();
    sb.write('OpMode: ');
    switch (opMode) {
      case kOpModeNull:
        sb.writeln('NULL');
        break;
      case kOpModeSta:
        sb.writeln('Station');
        break;
      case kOpModeSoftAP:
        sb.writeln('SoftAP');
        break;
      case kOpModeStaSoftAP:
        sb.writeln('Station/SoftAP');
        break;
      default:
        sb.writeln('Unknown');
    }

    if (opMode == kOpModeSta || opMode == kOpModeStaSoftAP) {
      sb.writeln(isStaConnected
          ? 'Station connected to Wi-Fi'
          : 'Station disconnected from Wi-Fi');
      if (staBSSID != null) sb.writeln('Station BSSID: $staBSSID');
      if (staSSID != null) sb.writeln('Station SSID: $staSSID');
      if (staPassword != null) sb.writeln('Station Password: $staPassword');
    }

    if (opMode == kOpModeSoftAP || opMode == kOpModeStaSoftAP) {
      if (softAPSSID != null) sb.writeln('SoftAP SSID: $softAPSSID');
      if (softAPPassword != null)
        sb.writeln('SoftAP Password: $softAPPassword');
      if (softAPChannel >= 0) sb.writeln('SoftAP Channel: $softAPChannel');
      if (softAPMaxConnCount > 0)
        sb.writeln('SoftAP Max Connections: $softAPMaxConnCount');
      if (softAPConnCount >= 0)
        sb.writeln('SoftAP Current Connections: $softAPConnCount');
    }

    return sb.toString();
  }
}
