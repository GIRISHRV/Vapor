import 'package:cryptography/cryptography.dart';
import 'dart:convert';

/// ECDH X25519 key pair generation for Key Exchange
Future<SimpleKeyPair> generateECDHKeyPair() async {
  final algorithm = X25519();
  return await algorithm.newKeyPair();
}

Future<SecretKey> deriveSharedSecret(
  SimpleKeyPair localKeyPair,
  PublicKey remotePublicKey,
  String roomId,
) async {
  final algorithm = X25519();
  final sharedSecret = await algorithm.sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: remotePublicKey,
  );

  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final nonce = utf8.encode(roomId);

  return await hkdf.deriveKey(secretKey: sharedSecret, nonce: nonce);
}

/// Serialize PublicKey to bytes
Future<List<int>> serializePublicKey(PublicKey key) async {
  if (key is SimplePublicKey) {
    return key.bytes;
  }
  throw UnsupportedError('Unsupported public key type: ${key.runtimeType}');
}

/// Deserialize PublicKey from bytes
PublicKey deserializePublicKey(List<int> bytes) {
  return SimplePublicKey(bytes, type: KeyPairType.x25519);
}
