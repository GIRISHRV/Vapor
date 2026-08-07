import 'dart:async';

// Web Stub (No-op on Web since it lacks raw sockets/mDNS)
class LocalCascadeEngine {
  bool get isConnected => false;
  Future<void> startBeacon(
    String roomId,
    Function(Map<String, dynamic>) onMessage,
  ) async {}
  Future<bool> scanAndConnect(
    String roomId,
    Function(Map<String, dynamic>) onMessage,
  ) async {
    return false;
  }

  void sendMessage(Map<String, dynamic> msg) {}
  Future<void> dispose() async {}
}
