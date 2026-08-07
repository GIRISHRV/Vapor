import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:app/crypto/aes_gcm.dart';

void main() {
  group('E2E Data Flow Tests', () {
    test(
      'Simulate complete file transfer flow (Key Exchange -> Metadata -> Encrypt -> Decrypt)',
      () async {
        // 1. Key Exchange Simulation (Mocked for pure Dart tests)
        // Since ECDH.p256 requires native plugins in flutter_cryptography, we mock the derived keys here
        final mockKeyBytes = List<int>.generate(
          32,
          (i) => i,
        ); // 32 bytes for AES-256
        final senderSessionKey = SecretKey(mockKeyBytes);
        final receiverSessionKey = SecretKey(mockKeyBytes);

        // 2. Metadata Transmission
        final manifest = [
          {'name': 'secret_plan.txt', 'size': 21},
        ];
        final metadataJson = jsonEncode(manifest);
        final metaChunk = await encryptChunk(
          Uint8List.fromList(utf8.encode(metadataJson)),
          senderSessionKey,
        );

        // Transmit over wire (simulated)
        final receivedMetaChunk = EncryptedChunk(
          nonce: metaChunk.nonce,
          ciphertext: metaChunk.ciphertext,
        );

        // Decrypt Metadata
        final decryptedMetaBytes = await decryptChunk(
          receivedMetaChunk,
          receiverSessionKey,
        );
        final receivedManifest = jsonDecode(utf8.decode(decryptedMetaBytes));
        expect(receivedManifest[0]['name'], equals('secret_plan.txt'));
        expect(receivedManifest[0]['size'], equals(21));

        // 3. File Transfer Simulation
        final fileData = Uint8List.fromList(
          utf8.encode('Hello from Sender!...'),
        ); // 21 bytes

        // Chunking (simulate chunk size 10)
        final chunkSize = 10;
        List<Uint8List> receivedFileBuffer = [];

        for (int i = 0; i < fileData.length; i += chunkSize) {
          final end = (i + chunkSize < fileData.length)
              ? i + chunkSize
              : fileData.length;
          final chunk = fileData.sublist(i, end);

          // Encrypt
          final encrypted = await encryptChunk(chunk, senderSessionKey);

          // Transmit (simulate wire format)
          final payload = Uint8List.fromList([
            0x03,
            ...encrypted.nonce,
            ...encrypted.ciphertext,
          ]);

          // Receive
          expect(payload[0], equals(0x03));
          final nonce = payload.sublist(1, 13);
          final ciphertext = payload.sublist(13);

          // Decrypt
          final decrypted = await decryptChunk(
            EncryptedChunk(nonce: nonce, ciphertext: ciphertext),
            receiverSessionKey,
          );
          receivedFileBuffer.add(Uint8List.fromList(decrypted));
        }

        // 4. Reassembly
        final builder = BytesBuilder();
        for (var b in receivedFileBuffer) {
          builder.add(b);
        }
        final finalData = builder.toBytes();

        expect(utf8.decode(finalData), equals('Hello from Sender!...'));
      },
    );
  });
}
