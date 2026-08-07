import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/panic_engine.dart';
import 'platform_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _platformOptions = <TargetPlatform?, _PlatformChoice>{
    null: _PlatformChoice('Auto (Native)', Icons.auto_awesome),
    TargetPlatform.android: _PlatformChoice(
      'Android (Material)',
      Icons.android,
    ),
    TargetPlatform.iOS: _PlatformChoice('iOS (Cupertino)', Icons.phone_iphone),
    TargetPlatform.macOS: _PlatformChoice('macOS (Apple)', Icons.desktop_mac),
    TargetPlatform.windows: _PlatformChoice(
      'Windows (Fluent)',
      Icons.desktop_windows,
    ),
    TargetPlatform.linux: _PlatformChoice('Linux', Icons.computer),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPlatform = ref.watch(platformOverrideProvider);
    final nativePlatform = defaultTargetPlatform;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- UI Style Section ---
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'Appearance',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'UI Style',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Native: ${_platformLabel(nativePlatform)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _platformOptions.entries.map((entry) {
                      final isSelected = currentPlatform == entry.key;
                      return ChoiceChip(
                        avatar: Icon(entry.value.icon, size: 18),
                        label: Text(entry.value.label),
                        selected: isSelected,
                        onSelected: (_) {
                          ref
                              .read(platformOverrideProvider.notifier)
                              .setPlatform(entry.key);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Security Section ---
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'Security',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text('Zero-Trust Architecture'),
                  subtitle: Text(
                    'All connections are ephemeral. No data is ever stored.',
                  ),
                  leading: Icon(Icons.security),
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text('Change App PINs'),
                  subtitle: const Text('Reset your Real PIN and Duress PIN.'),
                  leading: const Icon(Icons.pin),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('vapor_real_pin');
                    await prefs.remove('vapor_duress_pin');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PINs reset. Please set them again.'),
                        ),
                      );
                      context.go('/');
                    }
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text(
                    'Emergency Panic Wipe',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Instantly shred all active keys, wipe temp files, and close connections.',
                  ),
                  leading: const Icon(Icons.warning, color: Colors.red),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Initiate Panic Wipe?'),
                        content: const Text(
                          'This will instantly destroy all active session keys and wipe memory buffers. This cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCEL'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              PanicEngine.triggerPanicWipe(context);
                            },
                            child: const Text('WIPE'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- Network Diagnostics Section ---
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'Network Diagnostics',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Signaling Servers'),
                  subtitle: const Text(
                    'mDNS (Local) • Firebase (Cloud Fallback)',
                  ),
                  leading: const Icon(Icons.router, color: Colors.blue),
                  trailing: const Text(
                    'CONFIGURED',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text('NAT Traversal (STUN)'),
                  subtitle: const Text('stun.l.google.com:19302'),
                  leading: const Icon(Icons.public, color: Colors.blue),
                  trailing: const Text(
                    'CONFIGURED',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 0),
                ListTile(
                  title: const Text('P2P Protocol'),
                  subtitle: const Text('WebRTC (RTCDataChannel) multiplexed'),
                  leading: const Icon(Icons.compare_arrows, color: Colors.blue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- About Section ---
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'About',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Replay Welcome Tutorial'),
                  leading: const Icon(Icons.school),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/tutorial');
                  },
                ),
                const Divider(height: 0),
                const ListTile(
                  title: Text('Vapor v1.0.4'),
                  subtitle: Text(
                    'Zero-Trust Amnesiac P2P File Transfer Engine\nNo accounts. No history. No trace.',
                  ),
                  leading: Icon(Icons.info_outline),
                  isThreeLine: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _platformLabel(TargetPlatform p) {
    switch (p) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }
}

class _PlatformChoice {
  final String label;
  final IconData icon;
  const _PlatformChoice(this.label, this.icon);
}
