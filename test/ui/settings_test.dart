import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'vapor_real_pin': 'hashed_real_pin',
      'vapor_duress_pin': 'hashed_duress_pin',
      'vapor_pin_salt': 'some_salt',
    });
  });

  testWidgets('SettingsScreen layout and interactions', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SettingsScreen(),
    ));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Change Real PIN'), findsOneWidget);
    expect(find.text('Change Duress PIN'), findsOneWidget);
  });
}
