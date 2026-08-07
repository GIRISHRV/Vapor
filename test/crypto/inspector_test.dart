import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/crypto/inspector.dart';

void main() {
  group('SecurityInspector Tests', () {
    test('allows safe files', () {
      // JPEG magic bytes
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDB]);
      expect(() => SecurityInspector.inspectMagicBytes(jpeg), returnsNormally);

      // PNG magic bytes
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      expect(() => SecurityInspector.inspectMagicBytes(png), returnsNormally);

      // Random text
      final text = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
      expect(() => SecurityInspector.inspectMagicBytes(text), returnsNormally);

      // Empty or short bytes
      expect(
        () => SecurityInspector.inspectMagicBytes(Uint8List(0)),
        returnsNormally,
      );
      expect(
        () => SecurityInspector.inspectMagicBytes(Uint8List.fromList([0x4D])),
        returnsNormally,
      );
    });

    test('blocks Windows PE Executable (MZ)', () {
      final mz = Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00]);
      expect(
        () => SecurityInspector.inspectMagicBytes(mz),
        throwsA(isA<SecurityException>()),
      );
    });

    test('blocks ELF Executable', () {
      final elf = Uint8List.fromList([0x7F, 0x45, 0x4C, 0x46, 0x01]);
      expect(
        () => SecurityInspector.inspectMagicBytes(elf),
        throwsA(isA<SecurityException>()),
      );
    });

    test('blocks Mach-O Executable (CE)', () {
      final macho = Uint8List.fromList([0xFE, 0xED, 0xFA, 0xCE]);
      expect(
        () => SecurityInspector.inspectMagicBytes(macho),
        throwsA(isA<SecurityException>()),
      );
    });

    test('blocks Mach-O Executable (CF)', () {
      final macho = Uint8List.fromList([0xFE, 0xED, 0xFA, 0xCF]);
      expect(
        () => SecurityInspector.inspectMagicBytes(macho),
        throwsA(isA<SecurityException>()),
      );
    });

    test('blocks Mach-O reverse byte order (CE)', () {
      final machoRev = Uint8List.fromList([0xCE, 0xFA, 0xED, 0xFE]);
      expect(
        () => SecurityInspector.inspectMagicBytes(machoRev),
        throwsA(isA<SecurityException>()),
      );
    });

    test('blocks Java class file', () {
      final java = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      expect(
        () => SecurityInspector.inspectMagicBytes(java),
        throwsA(isA<SecurityException>()),
      );
    });

    test('blocks Shell Script (#!)', () {
      final shell = Uint8List.fromList([0x23, 0x21, 0x2F, 0x62, 0x69, 0x6E]);
      expect(
        () => SecurityInspector.inspectMagicBytes(shell),
        throwsA(isA<SecurityException>()),
      );
    });
  });
}
