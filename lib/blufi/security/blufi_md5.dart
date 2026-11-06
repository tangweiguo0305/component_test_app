import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class BlufiMD5 {
  static Uint8List getMD5Bytes(List<int> data) {
    final digest = md5.convert(data);
    return Uint8List.fromList(digest.bytes);
  }
}
