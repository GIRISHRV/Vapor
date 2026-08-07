import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:app/crypto/ecdh.dart';

void main() {
  group('ECDH Crypto Tests', () {
    test('generateECDHKeyPair should generate a valid key pair', () async {
      final keyPair = await generateECDHKeyPair();
      final publicKey = await keyPair.extractPublicKey();

      expect(publicKey.type, KeyPairType.x25519);

      expect(publicKey, isA<SimplePublicKey>());
      expect(publicKey.bytes.length, 32);
    });

    test(
      'deriveSharedSecret should produce the same secret for both parties',
      () async {
        final aliceKeyPair = await generateECDHKeyPair();
        final bobKeyPair = await generateECDHKeyPair();

        final alicePublicKey = await aliceKeyPair.extractPublicKey();
        final bobPublicKey = await bobKeyPair.extractPublicKey();

        final aliceSecret = await deriveSharedSecret(
          aliceKeyPair,
          bobPublicKey,
          'test-room',
        );
        final bobSecret = await deriveSharedSecret(
          bobKeyPair,
          alicePublicKey,
          'test-room',
        );

        final aliceSecretBytes = await aliceSecret.extractBytes();
        final bobSecretBytes = await bobSecret.extractBytes();

        expect(aliceSecretBytes, bobSecretBytes);
        expect(aliceSecretBytes.length, 32); // 256-bit AES key
      },
    );

    test(
      'serialize and deserialize public key should work correctly',
      () async {
        final keyPair = await generateECDHKeyPair();
        final publicKey = await keyPair.extractPublicKey();

        final serialized = await serializePublicKey(publicKey);
        expect(serialized.length, 32);

        final deserialized = deserializePublicKey(serialized);
        expect(deserialized, isA<SimplePublicKey>());

        final dPublicKey = deserialized as SimplePublicKey;
        final oPublicKey = publicKey;

        expect(dPublicKey.bytes, oPublicKey.bytes);
      },
    );
  });
}
