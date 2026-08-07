import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('DashboardScreen displays primary actions', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: DashboardScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // The Dashboard should have Send and Receive buttons (using custom widgets or text)
    expect(find.text('Send File'), findsWidgets);
    expect(find.text('Receive File'), findsWidgets);
  });
}
