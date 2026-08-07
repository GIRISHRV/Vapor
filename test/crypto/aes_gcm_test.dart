import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:app/crypto/aes_gcm.dart'; // Adjust import according to actual package name if needed

void main() {
  group('AES GCM Crypto Tests', () {
    test('generateAESKey should generate a valid SecretKey', () async {
      final key = await generateAESKey();
      final keyBytes = await key.extractBytes();
      expect(keyBytes.length, 32); // 256-bit key
    });

    test('encryptChunk and decryptChunk should work correctly', () async {
      final key = await generateAESKey();
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

      final encrypted = await encryptChunk(plaintext, key);

      expect(encrypted.nonce.length, 12); // Standard nonce length for AES-GCM
      expect(
        encrypted.ciphertext.length,
        plaintext.length + 16,
      ); // ciphertext + 16 bytes MAC

      final decrypted = await decryptChunk(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('decryptChunk should fail with wrong key', () async {
      final key = await generateAESKey();
      final wrongKey = await generateAESKey();
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

      final encrypted = await encryptChunk(plaintext, key);

      expect(
        () async => await decryptChunk(encrypted, wrongKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('decryptChunk should fail if ciphertext is tampered', () async {
      final key = await generateAESKey();
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

      final encrypted = await encryptChunk(plaintext, key);

      // Tamper with ciphertext
      encrypted.ciphertext[0] ^= 0xFF;

      expect(
        () async => await decryptChunk(encrypted, key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('decryptChunk should throw if ciphertext is too short', () async {
      final key = await generateAESKey();
      final shortCiphertext = Uint8List.fromList([
        1,
        2,
        3,
      ]); // Less than MAC length (16)

      final encrypted = EncryptedChunk(
        nonce: Uint8List(12),
        ciphertext: shortCiphertext,
      );

      expect(
        () async => await decryptChunk(encrypted, key),
        throwsArgumentError,
      );
    });
  });
}
