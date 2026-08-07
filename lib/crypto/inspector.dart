import 'dart:typed_data';

class SecurityInspector {
  /// Analyzes the first 16 bytes of a file to detect disguised executables.
  /// Throws a SecurityException if a banned signature is detected.
  static void inspectMagicBytes(Uint8List headerBytes) {
    if (headerBytes.length < 2) return;

    // Check for MZ (Windows PE Executable) - 4D 5A
    if (headerBytes[0] == 0x4D && headerBytes[1] == 0x5A) {
      throw const SecurityException(
        'Blocked: Detected Windows Executable (MZ) disguised as a safe file.',
      );
    }

    if (headerBytes.length >= 4) {
      // Check for ELF (Linux/Unix Executable) - 7F 45 4C 46
      if (headerBytes[0] == 0x7F &&
          headerBytes[1] == 0x45 &&
          headerBytes[2] == 0x4C &&
          headerBytes[3] == 0x46) {
        throw const SecurityException(
          'Blocked: Detected ELF Executable disguised as a safe file.',
        );
      }

      // Check for Mach-O (macOS/iOS) - FE ED FA CE or FE ED FA CF
      if (headerBytes[0] == 0xFE &&
          headerBytes[1] == 0xED &&
          headerBytes[2] == 0xFA &&
          (headerBytes[3] == 0xCE || headerBytes[3] == 0xCF)) {
        throw const SecurityException(
          'Blocked: Detected Mach-O Executable disguised as a safe file.',
        );
      }

      // Check for Mach-O reverse byte order - CE FA ED FE or CF FA ED FE
      if ((headerBytes[0] == 0xCE || headerBytes[0] == 0xCF) &&
          headerBytes[1] == 0xFA &&
          headerBytes[2] == 0xED &&
          headerBytes[3] == 0xFE) {
        throw const SecurityException(
          'Blocked: Detected Mach-O Executable disguised as a safe file.',
        );
      }

      // Check for Java class file (CAFEBABE)
      if (headerBytes[0] == 0xCA &&
          headerBytes[1] == 0xFE &&
          headerBytes[2] == 0xBA &&
          headerBytes[3] == 0xBE) {
        throw const SecurityException(
          'Blocked: Detected Java class file disguised as a safe file.',
        );
      }
    }

    // Check for shell scripts (#!)
    if (headerBytes[0] == 0x23 && headerBytes[1] == 0x21) {
      throw const SecurityException(
        'Blocked: Detected shell script disguised as a safe file.',
      );
    }
  }
}

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => message;
}
