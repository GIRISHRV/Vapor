import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'components/vapor_components.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _networkStatus = "Checking...";
  Color _networkColor = Colors.grey;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _checkSetup();
    _initConnectivity();
  }

  Future<void> _checkSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('has_seen_tutorial') ?? false;
    if (!hasSeen && mounted) {
      context.go('/tutorial');
    }
  }

  void _initConnectivity() {
    Connectivity().checkConnectivity().then(_updateConnectionStatus);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (!mounted) return;
    
    // In connectivity_plus > 5.0.0, it returns a List<ConnectivityResult>
    final hasInternet = results.any((r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile || r == ConnectivityResult.ethernet);
    final hasVpn = results.contains(ConnectivityResult.vpn);
    
    setState(() {
      if (hasInternet && hasVpn) {
        _networkStatus = "Secure VPN Tunnel Active";
        _networkColor = Colors.greenAccent;
      } else if (hasInternet) {
        _networkStatus = "Online - Ready to Connect";
        _networkColor = Colors.green;
      } else {
        _networkStatus = "Offline - Local Transfers Only";
        _networkColor = Colors.orange;
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Icon(
                  Icons.lock_outline,
                  size: 80,
                  color: isDark ? Colors.white : Colors.black,
                ).animate().fade(duration: 500.ms).scale(curve: Curves.easeOutBack),
                const SizedBox(height: 24),
                Text(
                  'Zero-Trust\nFile Transfer',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ).animate().fade(delay: 200.ms).slideY(begin: 0.2, curve: Curves.easeOut),
                const SizedBox(height: 16),
                Text(
                  'End-to-end encrypted. No servers.\nNo traces left behind.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ).animate().fade(delay: 300.ms).slideY(begin: 0.2, curve: Curves.easeOut),
                
                const SizedBox(height: 24),
                
                // Network Diagnostics Pill
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _networkColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _networkColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: _networkColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _networkStatus,
                          style: TextStyle(color: _networkColor, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ).animate().fade(delay: 400.ms),
            
                const SizedBox(height: 48),
                
                VaporCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ActionTile(
                        icon: Icons.send_rounded,
                        title: 'Send File',
                        subtitle: 'Generate a secure link',
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          context.push('/send');
                        },
                      ),
                      Divider(height: 1, indent: 72, color: isDark ? Colors.white12 : Colors.black12),
                      _ActionTile(
                        icon: Icons.download_rounded,
                        title: 'Receive File',
                        subtitle: 'Enter a code to connect',
                        onPressed: () {
                          HapticFeedback.heavyImpact();
                          context.push('/receive');
                        },
                      ),
                    ],
                  ),
                ).animate().fade(delay: 500.ms).slideY(begin: 0.2, curve: Curves.easeOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: isDark ? Colors.white : Colors.black),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
