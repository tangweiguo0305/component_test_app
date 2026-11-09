import 'dart:math';
import 'dart:typed_data';

/// Diffie-Hellman 密钥协商，与 Java 版 BlufiDH 使用相同的 P/G 参数
class BlufiDH {
  static final BigInt _p = BigInt.parse(
    'cf5cf5c38419a724957ff5dd323b9c45c3cdd261eb740f69aa94b8bb1a5c9640'
    '9153bd76b24222d03274e4725a5406092e9e82e9135c643cae98132b0d95f7d6'
    '5347c68afc1e677da90e51bbab5f5cf429c291b4ba39c6b2dc5e8c7231e46aa7'
    '728e87664532cdf547be20c9a3fa8342be6e34371a27c06f7dc0edddd2f86373',
    radix: 16,
  );
  static final BigInt _g = BigInt.two;

  late final BigInt _privateKey;
  late final BigInt publicKey;

  BlufiDH() {
    _privateKey = _generatePrivateKey();
    publicKey = _g.modPow(_privateKey, _p);
  }

  BigInt _generatePrivateKey() {
    final rng = Random.secure();
    final byteCount = 128; // 1024 bits
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return BigInt.parse(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    );
  }

  /// 用设备公钥生成共享密钥
  Uint8List generateSharedSecret(BigInt devicePublicKey) {
    final secret = devicePublicKey.modPow(_privateKey, _p);
    final hex = secret.toRadixString(16).padLeft(256, '0');
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// 将公钥转为 256 字节 hex 字符串
  String get publicKeyHex => publicKey.toRadixString(16).padLeft(256, '0');

  BigInt get p => _p;
  BigInt get g => _g;
}
