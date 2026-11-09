import 'dart:typed_data';

class BlufiConfigureParams {
  int opMode = 0;

  String? staBSSID;
  Uint8List? staSSIDBytes;
  String? staPassword;
  String? authData; // 新增：认证数据，配网前通过分页自定义数据协议发送

  int softAPSecurity = 0;
  String? softAPSSID;
  String? softAPPassword;
  int softAPChannel = 0;
  int softAPMaxConnection = 0;

  @override
  String toString() {
    return 'opMode=$opMode, staBSSID=$staBSSID, '
        'staSSID=${staSSIDBytes != null ? String.fromCharCodes(staSSIDBytes!) : null}, '
        'staPassword=$staPassword, softAPSecurity=$softAPSecurity, '
        'softAPSSID=$softAPSSID, softAPPassword=$softAPPassword, '
        'softAPChannel=$softAPChannel, softAPMaxConnection=$softAPMaxConnection';
  }
}
