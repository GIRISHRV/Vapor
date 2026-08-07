import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

class AppTheme {
  static ThemeData getTheme({
    required Brightness brightness,
    TargetPlatform? platformOverride,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final TargetPlatform platform = platformOverride ?? defaultTargetPlatform;
    final Color primary = _getPlatformPrimaryColor(platform);

    ThemeData theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: primary,
      brightness: brightness,
      platform: platform,
    );

    // Apply Platform-Specific Design Adaptations
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        theme = theme.copyWith(
          // No ripple effect on Apple platforms
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          pageTransitionsTheme: PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
              TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
            },
          ),
          appBarTheme: theme.appBarTheme.copyWith(
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: isDark
                ? const Color(0xFF1C1C1E)
                : const Color(0xFFF2F2F7),
          ),
          scaffoldBackgroundColor: isDark
              ? Colors.black
              : const Color(0xFFF2F2F7),
          filledButtonTheme: platform == TargetPlatform.macOS
              ? _macOSButtonTheme()
              : null,
          cardTheme: platform == TargetPlatform.macOS
              ? _macOSCardTheme()
              : null,
          dialogTheme: platform == TargetPlatform.macOS
              ? _macOSDialogTheme()
              : null,
        );
        break;

      case TargetPlatform.windows:
        theme = theme.copyWith(
          visualDensity: VisualDensity.compact,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          pageTransitionsTheme: PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.windows: const FadeUpwardsPageTransitionsBuilder(),
            },
          ),
          filledButtonTheme: _windowsButtonTheme(),
          cardTheme: _windowsCardTheme(),
          dialogTheme: _windowsDialogTheme(),
          inputDecorationTheme: _windowsInputTheme(),
        );
        break;

      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        // Material 3 defaults are excellent for Android
        break;

      case TargetPlatform.linux:
        theme = theme.copyWith(visualDensity: VisualDensity.compact);
        break;
    }

    return theme;
  }

  static Color _getPlatformPrimaryColor(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const Color(0xFF007AFF); // Apple Blue
      case TargetPlatform.windows:
        return const Color(0xFF0078D4); // Fluent Blue
      default:
        return Colors.blue; // Material Default
    }
  }

  // --- Windows (Fluent) Themes ---
  static FilledButtonThemeData _windowsButtonTheme() => FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );

  static CardThemeData _windowsCardTheme() => CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    elevation: 2,
  );

  static DialogThemeData _windowsDialogTheme() => DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  static InputDecorationTheme _windowsInputTheme() => InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
  );

  // --- macOS Themes ---
  static FilledButtonThemeData _macOSButtonTheme() => FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );

  static CardThemeData _macOSCardTheme() => CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 1,
  );

  static DialogThemeData _macOSDialogTheme() => DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
