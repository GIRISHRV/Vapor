import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PanicEngine {
  /// The globally registered secret key references that must be wiped on duress.
  static final List<Uint8List> _activeKeyMaterial = [];

  /// Globally registered teardown callbacks (WebRTC close, signaling purge, etc.)
  static final List<Future<void> Function()> _teardownCallbacks = [];

  static void registerKeyMaterial(Uint8List keyBytes) {
    _activeKeyMaterial.add(keyBytes);
  }

  static void unregisterKeyMaterial(Uint8List keyBytes) {
    _activeKeyMaterial.remove(keyBytes);
  }

  /// Register a teardown callback (e.g. close WebRTC, purge Firebase room)
  static void registerTeardown(Future<void> Function() callback) {
    _teardownCallbacks.add(callback);
  }

  static void clearTeardowns() {
    _teardownCallbacks.clear();
  }

  /// Triggers the emergency duress protocol
  static Future<void> triggerPanicWipe(BuildContext context) async {
    // 1. Overwrite cryptographic keys in memory with random bytes
    final random = Random.secure();
    for (var keyBytes in _activeKeyMaterial) {
      for (int i = 0; i < keyBytes.length; i++) {
        keyBytes[i] = random.nextInt(256);
      }
    }
    _activeKeyMaterial.clear();

    // 2. Execute all registered teardown callbacks (WebRTC, Signaling, Mist)
    for (var teardown in _teardownCallbacks) {
      try {
        await teardown();
      } catch (_) {
        // Best-effort during panic
      }
    }
    _teardownCallbacks.clear();

    // 3. Purge Temp Buffers (only on native platforms — dart:io not available on Web)
    if (!kIsWeb) {
      try {
        // Dynamic import to avoid dart:io compilation issues on web
        await _purgeNativeTempFiles(random);
      } catch (_) {
        // Ignore deletion errors during panic wipe
      }
    }

    // 4. Transition seamlessly to the default dashboard without error popups
    if (context.mounted) {
      while (context.canPop()) {
        context.pop();
      }
      context.go('/');
    }
  }

  /// Native-only temp file purge. Isolated so web builds can tree-shake it.
  static Future<void> _purgeNativeTempFiles(Random random) async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final entities = tempDir.listSync(recursive: false);
      for (var entity in entities) {
        if (entity is File) {
          try {
            // Overwrite file with random bytes before deleting
            final length = await entity.length();
            if (length > 0) {
              final raf = await entity.open(mode: FileMode.write);
              final randomBytes = Uint8List(
                length > 1024 * 1024 ? 1024 * 1024 : length,
              ); // cap to 1MB to avoid memory limits
              for (int i = 0; i < randomBytes.length; i++) {
                randomBytes[i] = random.nextInt(256);
              }
              await raf.writeFrom(randomBytes);
              await raf.close();
            }
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
