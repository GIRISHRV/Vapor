import 'dart:io';
import 'dart:typed_data';

class FileChunker {
  static const int chunkSize =
      64 * 1024; // 64 KB chunks for optimal WebRTC transport

  /// Generates chunks of the file asynchronously, resuming from a specific offset if needed.
  static Stream<Uint8List> streamFile(
    File file, {
    int resumeOffset = 0,
  }) async* {
    final raf = await file.open(mode: FileMode.read);
    try {
      if (resumeOffset > 0) {
        await raf.setPosition(resumeOffset);
      }

      while (true) {
        final buffer = await raf.read(chunkSize);
        if (buffer.isEmpty) {
          break; // EOF
        }
        yield buffer;
      }
    } finally {
      await raf.close();
    }
  }

  /// Collects chunks into a single file on disk (or OPFS temp directory)
  static Future<void> writeChunk(
    File targetFile,
    Uint8List chunk, {
    required bool append,
  }) async {
    final mode = append ? FileMode.append : FileMode.write;
    final raf = await targetFile.open(mode: mode);
    try {
      await raf.writeFrom(chunk);
    } finally {
      await raf.close();
    }
  }
}
