import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier that holds an optional platform override.
/// When null, the native platform is used.
class PlatformOverrideNotifier extends Notifier<TargetPlatform?> {
  @override
  TargetPlatform? build() => null;

  void setPlatform(TargetPlatform? platform) {
    state = platform;
  }
}

final platformOverrideProvider =
    NotifierProvider<PlatformOverrideNotifier, TargetPlatform?>(
      PlatformOverrideNotifier.new,
    );
