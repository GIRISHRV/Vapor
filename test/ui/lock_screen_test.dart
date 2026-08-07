import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/ui/lock_screen.dart'; // Adjust path if needed


// Helper to match the PBKDF2 structure roughly, or just mock it since the lock screen
// will use the actual PBKDF2. Wait, the lock screen uses PBKDF2 now. 
// Since PBKDF2 is async and built-in to the package, it will work in tests.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('LockScreenOverlay shows Setup Mode on first run', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LockScreenOverlay(),
      ),
    ));

    // Wait for async init
    await tester.pumpAndSettle();

    expect(find.text('Create Real PIN'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget); // Numpad
  });

  testWidgets('LockScreenOverlay setup flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LockScreenOverlay(),
      ),
    ));
    await tester.pumpAndSettle();

    // 1. Create Real PIN (1234)
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle(); // Processing delay (Future.delayed)

    expect(find.text('Confirm Real PIN'), findsOneWidget);

    // 2. Confirm Real PIN (1234)
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    expect(find.text('Create Duress (Wipe) PIN'), findsOneWidget);

    // 3. Create Duress PIN (9999)
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm Duress PIN'), findsOneWidget);

    // 4. Confirm Duress PIN (9999)
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();

    // Should finish setup and pop (which in this test will just dismiss since no GoRouter, but onUnlock is not null so it might call it)
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vapor_pin_salt'), isNotNull);
    expect(prefs.getString('vapor_real_pin'), isNotNull);
    expect(prefs.getString('vapor_duress_pin'), isNotNull);
  });
}
