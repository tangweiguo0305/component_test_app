import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// AES/CFB8/NoPadding 加解密，与 Java 版 BlufiAES 一致
/// pointycastle 的 CFBBlockCipher 不支持真正的 CFB8 流式处理，
/// 因此手动实现 CFB8：每次用 AES-ECB 加密 IV，取第一字节与明文 XOR，然后移位 IV
class BlufiAES {
  final Uint8List _key;
  final Uint8List _iv;

  BlufiAES(List<int> key, List<int> iv)
      : _key = Uint8List.fromList(key),
        _iv = Uint8List.fromList(iv);

  Uint8List encrypt(List<int> data) => _cfb8(true, Uint8List.fromList(data));
  Uint8List decrypt(List<int> data) => _cfb8(false, Uint8List.fromList(data));

  Uint8List _cfb8(bool forEncryption, Uint8List input) {
    // AES-ECB 引擎，用于加密 IV
    final aes = AESEngine()..init(true, KeyParameter(_key));

    final iv = Uint8List.fromList(_iv); // 工作 IV，逐字节移位
    final output = Uint8List(input.length);
    final block = Uint8List(16);

    for (var i = 0; i < input.length; i++) {
      // 1. 用 AES-ECB 加密当前 IV
      aes.processBlock(iv, 0, block, 0);

      // 2. 取加密结果第一字节与输入 XOR
      final inByte = input[i];
      final outByte = (block[0] ^ inByte) & 0xff;
      output[i] = outByte;

      // 3. 移位 IV：左移一字节，末位填入密文字节
      // 加密时密文 = outByte，解密时密文 = inByte
      final cipherByte = forEncryption ? outByte : inByte;
      iv.setRange(0, 15, iv, 1);
      iv[15] = cipherByte;
    }

    return output;
  }
}
