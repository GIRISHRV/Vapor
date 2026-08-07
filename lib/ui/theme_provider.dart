import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDesignStyle {
  material('Material 3'),
  cupertino('Apple Glassmorphism'),
  fluent('Windows Fluent UI');

  final String label;
  const AppDesignStyle(this.label);
}

class DesignStyleNotifier extends Notifier<AppDesignStyle> {
  @override
  AppDesignStyle build() {
    return AppDesignStyle.material; // Default to Material
  }

  void setStyle(AppDesignStyle style) {
    state = style;
  }
}

final designStyleProvider = NotifierProvider<DesignStyleNotifier, AppDesignStyle>(
  () => DesignStyleNotifier(),
);
