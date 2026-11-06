import 'blufi_parameter.dart';

/// FrameCtrl 帧控制字节解析与生成
class FrameCtrl {
  static const int _posEncrypted = 0;
  static const int _posChecksum = 1;
  static const int _posDirection = 2;
  static const int _posRequireAck = 3;
  static const int _posFrag = 4;

  final int value;
  const FrameCtrl(this.value);

  bool get isEncrypted => _check(_posEncrypted);
  bool get isChecksum => _check(_posChecksum);
  bool get isRequireAck => _check(_posRequireAck);
  bool get hasFrag => _check(_posFrag);

  bool _check(int pos) => ((value >> pos) & 1) == 1;

  static int build({
    bool encrypted = false,
    bool checksum = false,
    int direction = kDirectionOutput,
    bool requireAck = false,
    bool frag = false,
  }) {
    int frame = 0;
    if (encrypted) frame |= (1 << _posEncrypted);
    if (checksum) frame |= (1 << _posChecksum);
    if (direction == kDirectionInput) frame |= (1 << _posDirection);
    if (requireAck) frame |= (1 << _posRequireAck);
    if (frag) frame |= (1 << _posFrag);
    return frame;
  }
}

/// 接收到的通知数据缓冲
class BlufiNotifyData {
  int type = 0;
  int pkgType = 0;
  int subType = 0;
  int frameCtrl = 0;
  final List<int> _data = [];

  void addData(List<int> bytes, int offset) {
    _data.addAll(bytes.sublist(offset));
  }

  List<int> get dataBytes => List.unmodifiable(_data);
}
