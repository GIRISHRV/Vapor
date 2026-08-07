import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../crypto/panic_engine.dart';
import 'components/vapor_components.dart';

class AdaptiveShell extends StatelessWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/send')) return 1;
    if (location.startsWith('/receive')) return 2;
    if (location.startsWith('/mist')) return 3;
    return 0; // dashboard
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 768) {
          // Desktop/Tablet: Full-height NavigationRail
          final bool isExtended = constraints.maxWidth >= 1024;
          return VaporScaffold(
            hideAppBar: true,
            body: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.02)
                        : Colors.black.withValues(alpha: 0.02),
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/icon.png', height: 28, width: 28),
                            if (isExtended) ...[
                              const SizedBox(width: 12),
                              const Text(
                                'Vapor',
                                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                              ),
                            ]
                          ],
                        ),
                      ),
                      Expanded(
                        child: NavigationRail(
                          extended: isExtended,
                          minExtendedWidth: 160,
                          minWidth: 64,
                          backgroundColor: Colors.transparent,
                          selectedIndex: _calculateSelectedIndex(context),
                          onDestinationSelected: (idx) => _handleNav(idx, context),
                          labelType: isExtended
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          useIndicator: true,
                          unselectedLabelTextStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7)),
                          selectedLabelTextStyle: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.dashboard_outlined),
                              selectedIcon: Icon(Icons.dashboard),
                              label: Text('Home'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.send_outlined),
                              selectedIcon: Icon(Icons.send),
                              label: Text('Send'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.download_outlined),
                              selectedIcon: Icon(Icons.download),
                              label: Text('Receive'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.hub_outlined),
                              selectedIcon: Icon(Icons.hub),
                              label: Text('Groups'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.warning_amber_rounded, color: Colors.red),
                              selectedIcon: Icon(Icons.warning, color: Colors.red),
                              label: Text('Wipe', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.settings),
                              tooltip: 'Settings',
                              onPressed: () => context.push('/settings'),
                            ),
                            const SizedBox(height: 12),
                            IconButton(
                              icon: const Icon(Icons.lock_outline),
                              tooltip: 'Lock Workspace',
                              onPressed: () => context.push('/lock'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          );
        } else {
          // Mobile: BottomNavigationBar
          return VaporScaffold(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icon.png', height: 28, width: 28),
                const SizedBox(width: 12),
                const Text(
                  'Vapor',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Lock Workspace',
                onPressed: () => context.push('/lock'),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
            ],
            body: child,
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1), width: 1)),
              ),
              child: NavigationBar(
                selectedIndex: _calculateSelectedIndex(context),
                onDestinationSelected: (idx) => _handleNav(idx, context),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.send_outlined),
                    selectedIcon: Icon(Icons.send),
                    label: 'Send',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.download_outlined),
                    selectedIcon: Icon(Icons.download),
                    label: 'Receive',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.hub_outlined),
                    selectedIcon: Icon(Icons.hub),
                    label: 'Groups',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.warning_amber_rounded, color: Colors.red),
                    selectedIcon: Icon(Icons.warning, color: Colors.red),
                    label: 'Wipe',
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }


  void _handleNav(int index, BuildContext context) {
    if (index == 4) {
      _showWipeConfirmation(context);
      return;
    }
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/send');
        break;
      case 2:
        context.go('/receive');
        break;
      case 3:
        context.go('/mist');
        break;
    }
  }

  void _showWipeConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 12),
            const Text('Confirm Wipe'),
          ],
        ),
        content: const Text(
          'Are you sure you want to instantly shred all cryptographic keys and sever connections?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _executeWipe(context);
            },
            child: const Text('WIPE'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeWipe(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        title: Row(
          children: [
            Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Text(
              'EMERGENCY WIPE',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Shredding cryptographic keys and temp buffers...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1500));

    if (context.mounted) {
      await PanicEngine.triggerPanicWipe(context);
    }
  }
}
