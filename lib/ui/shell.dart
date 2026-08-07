import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../crypto/panic_engine.dart';

class AdaptiveShell extends StatelessWidget {
  final Widget child;

  const AdaptiveShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/send')) return 1;
    if (location.startsWith('/receive')) return 2;
    if (location.startsWith('/swarm')) return 3;
    return 0; // dashboard
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 768) {
          // Desktop/Tablet: NavigationRail
          return Scaffold(
            appBar: _buildGlobalAppBar(context),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _calculateSelectedIndex(context),
                  onDestinationSelected: (idx) => _handleNav(idx, context),
                  labelType: NavigationRailLabelType.all,
                  useIndicator: true,
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
                      label: Text('Swarm'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                      ),
                      selectedIcon: Icon(Icons.warning, color: Colors.red),
                      label: Text('Wipe', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: child),
              ],
            ),
          );
        } else {
          // Mobile: BottomNavigationBar
          return Scaffold(
            appBar: _buildGlobalAppBar(context),
            body: child,
            bottomNavigationBar: NavigationBar(
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
                  label: 'Swarm',
                ),
                NavigationDestination(
                  icon: Icon(Icons.warning_amber_rounded, color: Colors.red),
                  selectedIcon: Icon(Icons.warning, color: Colors.red),
                  label: 'Wipe',
                ),
              ],
            ),
          );
        }
      },
    );
  }

  AppBar _buildGlobalAppBar(BuildContext context) {
    return AppBar(
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
      centerTitle: false,
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
        context.go('/swarm');
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
