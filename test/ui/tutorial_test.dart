import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/ui/tutorial_slides.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Tutorial slides navigation', (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/tutorial',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home Screen')),
        ),
        GoRoute(
          path: '/tutorial',
          builder: (context, state) => const TutorialSlidesScreen(),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    // Slide 1
    expect(find.text('Welcome to Vapor'), findsOneWidget);
    expect(find.text('NEXT'), findsOneWidget);
    
    // Tap Next
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    // Slide 2
    expect(find.text('Zero-Persistence'), findsOneWidget);
    
    // Tap Next
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    // Slide 3
    expect(find.text('Hybrid Cascade Router'), findsOneWidget);
    
    // Tap Next
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    // Slide 4
    expect(find.text('Emergency Duress'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);

    // Tap START
    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();

    // After START, it navigates to '/'
    expect(find.text('Home Screen'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('has_seen_tutorial'), isTrue);
  });
}
