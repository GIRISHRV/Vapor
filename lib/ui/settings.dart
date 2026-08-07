import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../crypto/panic_engine.dart';
import 'theme_provider.dart';
import 'components/vapor_components.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isOnline = true;
  StreamSubscription? _connSub;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() {
        _isOnline = !results.contains(ConnectivityResult.none);
      });
    });
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() {
      _isOnline = !results.contains(ConnectivityResult.none);
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStyle = ref.watch(designStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return VaporScaffold(
      title: 'Settings',
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, size: 20, color: isDark ? Colors.white : Colors.black),
        onPressed: () {
          HapticFeedback.lightImpact();
          context.pop();
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- UI Style Section ---
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'Appearance',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          VaporCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: AppDesignStyle.values.map((style) {
                return Column(
                  children: [
                    VaporListTile(
                      title: Text(style.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                      leading: Icon(
                        style == AppDesignStyle.material ? Icons.android :
                        style == AppDesignStyle.cupertino ? Icons.apple : Icons.window,
                      ),
                      trailing: currentStyle == style 
                          ? Icon(Icons.check_circle, color: isDark ? Colors.white : Colors.black)
                          : const SizedBox.shrink(),
                      onTap: () {
                        ref.read(designStyleProvider.notifier).setStyle(style);
                      },
                    ),
                    if (style != AppDesignStyle.values.last)
                      Divider(height: 1, indent: 56, color: isDark ? Colors.white12 : Colors.black12),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // --- Security Section ---
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text(
              'Security',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          VaporCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                VaporListTile(
                  title: const Text('Zero-Trust Architecture'),
                  subtitle: const Text('All connections are ephemeral. No data is ever stored.', style: TextStyle(fontSize: 12)),
                  leading: const Icon(Icons.security),
                ),
                Divider(height: 1, indent: 56, color: isDark ? Colors.white12 : Colors.black12),
                VaporListTile(
                  title: const Text('Change App PINs'),
                  subtitle: const Text('Reset your Real PIN and Duress PIN.', style: TextStyle(fontSize: 12)),
                  leading: const Icon(Icons.pin),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('vapor_real_pin');
                    await prefs.remove('vapor_duress_pin');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PINs reset. Please set them again.')),
                      );
                      context.go('/lock');
                    }
                  },
                ),
                Divider(height: 1, indent: 56, color: isDark ? Colors.white12 : Colors.black12),
                VaporListTile(
                  title: const Text('Trigger Panic Wipe', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Instantly destroy all keys and locks.', style: TextStyle(fontSize: 12)),
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  onTap: () async {
                    await PanicEngine.triggerPanicWipe(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PANIC WIPE EXECUTED. Restarting app.')),
                      );
                      context.go('/tutorial');
                    }
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
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          VaporCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                VaporListTile(
                  title: const Text('Signaling Servers'),
                  subtitle: const Text('mDNS (Local) • Firebase (Cloud Fallback)', style: TextStyle(fontSize: 12)),
                  leading: const Icon(Icons.router, color: Colors.blue),
                  trailing: Text(_isOnline ? 'ONLINE' : 'OFFLINE', style: TextStyle(color: _isOnline ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                Divider(height: 1, indent: 56, color: isDark ? Colors.white12 : Colors.black12),
                VaporListTile(
                  title: const Text('NAT Traversal (STUN)'),
                  subtitle: const Text('stun.l.google.com:19302', style: TextStyle(fontSize: 12)),
                  leading: const Icon(Icons.public, color: Colors.blue),
                  trailing: Text(_isOnline ? 'ONLINE' : 'OFFLINE', style: TextStyle(color: _isOnline ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                Divider(height: 1, indent: 56, color: isDark ? Colors.white12 : Colors.black12),
                const VaporListTile(
                  title: Text('P2P Protocol'),
                  subtitle: Text('WebRTC (RTCDataChannel) multiplexed', style: TextStyle(fontSize: 12)),
                  leading: Icon(Icons.compare_arrows, color: Colors.blue),
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
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          VaporCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                VaporListTile(
                  title: const Text('Replay Welcome Tutorial'),
                  leading: const Icon(Icons.school),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/tutorial');
                  },
                ),
                Divider(height: 1, indent: 56, color: isDark ? Colors.white12 : Colors.black12),
                const VaporListTile(
                  title: Text('Vapor v1.1.0'),
                  subtitle: Text(
                    'Zero-Trust Amnesiac P2P File Transfer Engine\nNo accounts. No history. No trace.',
                    style: TextStyle(fontSize: 12),
                  ),
                  leading: Icon(Icons.info_outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
