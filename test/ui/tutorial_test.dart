import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/tutorial_slides.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Tutorial slides navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TutorialSlidesScreen(),
    ));

    // Slide 1
    expect(find.text('Zero-Trust Architecture'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    
    // Tap Next
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Slide 2
    expect(find.text('No Servers. No Traces.'), findsOneWidget);
    
    // Tap Next
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Slide 3
    expect(find.text('Duress PIN'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Get Started
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('has_seen_tutorial'), isTrue);
  });
}
