import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'ui/theme.dart';
import 'ui/shell.dart';
import 'ui/send_workspace.dart';
import 'ui/receive_inbox.dart';
import 'ui/dashboard.dart';
import 'ui/swarm_mesh.dart';
import 'ui/lock_screen.dart';
import 'ui/tutorial_slides.dart';
import 'ui/settings.dart';
import 'ui/platform_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

/// Global flag: set to true before opening the OS file picker so the app
/// doesn't re-lock itself when the picker briefly backgrounds the app.
class AppState {
  static bool ignoreNextResume = false;
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const ProviderScope(child: MyApp()));
  } catch (e, stackTrace) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                'FATAL LAUNCH ERROR:\n\n$e\n\n$stackTrace',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _isLocked = true;
  bool _isLoading = true;
  StreamSubscription<Uri>? _appLinksSub;
  late AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialLock();
    _initAppLinks();
  }

  void _initAppLinks() {
    _appLinks = AppLinks();
    _appLinksSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'vapor' && uri.host == 'room') {
        final code = uri.queryParameters['code'];
        final exp = uri.queryParameters['exp'];
        if (code != null) {
          _router.go('/receive', extra: {'code': code, 'exp': exp});
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appLinksSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (AppState.ignoreNextResume) {
        // File picker is opening — skip re-lock
        AppState.ignoreNextResume = false;
        return;
      }
      // Genuine background — re-lock for security
      setState(() => _isLocked = true);
    }
  }

  late GoRouter _router;

  Future<void> _checkInitialLock() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTutorial = prefs.getBool('has_seen_tutorial') ?? false;

    _router = GoRouter(
      initialLocation: hasSeenTutorial ? '/' : '/tutorial',
      routes: [
        GoRoute(
          path: '/tutorial',
          builder: (context, state) => const TutorialSlidesScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/lock',
          builder: (context, state) =>
              LockScreenOverlay(onUnlock: () => context.go('/')),
        ),
        ShellRoute(
          builder: (context, state, child) => AdaptiveShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/send',
              builder: (context, state) => const SendWorkspaceScreen(),
            ),
            GoRoute(
              path: '/receive',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>?;
                return ReceiveInboxScreen(
                  initialCode: extra?['code']?.toString(),
                  initialExtra: extra,
                );
              },
            ),
            GoRoute(
              path: '/swarm',
              builder: (context, state) => const SwarmMeshScreen(),
            ),
          ],
        ),
      ],
    );

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final currentPlatform = ref.watch(platformOverrideProvider);

    return MaterialApp.router(
      title: 'Vapor Engine',
      theme: AppTheme.getTheme(
        brightness: Brightness.dark,
        platformOverride: currentPlatform,
      ),
      darkTheme: AppTheme.getTheme(
        brightness: Brightness.dark,
        platformOverride: currentPlatform,
      ),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      builder: (context, child) {
        return Stack(
          children: [
            ?child,
            if (_isLocked)
              Positioned.fill(
                child: LockScreenOverlay(
                  onUnlock: () => setState(() => _isLocked = false),
                ),
              ),
          ],
        );
      },
    );
  }
}
