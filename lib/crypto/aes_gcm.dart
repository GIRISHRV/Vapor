import 'package:cryptography/cryptography.dart';

import 'dart:typed_data';

class EncryptedChunk {
  final Uint8List nonce;
  final Uint8List ciphertext;

  EncryptedChunk({required this.nonce, required this.ciphertext});
}

/// Generate a new AES-256-GCM key.
Future<SecretKey> generateAESKey() async {
  final algorithm = AesGcm.with256bits();
  return await algorithm.newSecretKey();
}

/// Encrypt a single chunk of data.
/// A fresh nonce (IV) is generated for every encryption call.
Future<EncryptedChunk> encryptChunk(
  Uint8List plaintextChunk,
  SecretKey secretKey,
) async {
  final algorithm = AesGcm.with256bits();
  final secretBox = await algorithm.encrypt(
    plaintextChunk,
    secretKey: secretKey,
  );

  // Combine ciphertext and MAC into a single array for transmission
  final combinedCiphertext = Uint8List(
    secretBox.cipherText.length + secretBox.mac.bytes.length,
  );
  combinedCiphertext.setAll(0, secretBox.cipherText);
  combinedCiphertext.setAll(secretBox.cipherText.length, secretBox.mac.bytes);

  return EncryptedChunk(
    nonce: Uint8List.fromList(secretBox.nonce),
    ciphertext: combinedCiphertext,
  );
}

/// Decrypt a single chunk of data.
Future<Uint8List> decryptChunk(
  EncryptedChunk chunk,
  SecretKey secretKey,
) async {
  final algorithm = AesGcm.with256bits();

  final macLength = 16;
  if (chunk.ciphertext.length < macLength) {
    throw ArgumentError('Ciphertext is too short to contain a MAC.');
  }

  final actualCiphertext = chunk.ciphertext.sublist(
    0,
    chunk.ciphertext.length - macLength,
  );
  final macBytes = chunk.ciphertext.sublist(
    chunk.ciphertext.length - macLength,
  );

  final reconstructedBox = SecretBox(
    actualCiphertext,
    nonce: chunk.nonce,
    mac: Mac(macBytes),
  );

  final decrypted = await algorithm.decrypt(
    reconstructedBox,
    secretKey: secretKey,
  );
  return Uint8List.fromList(decrypted);
}
