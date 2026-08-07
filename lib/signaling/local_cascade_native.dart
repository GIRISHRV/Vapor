import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;

class LocalCascadeEngine {
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  HttpServer? _server;
  WebSocket? _socket;
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;

  Function(Map<String, dynamic>)? _onMessage;

  // SENDER (Host): Spin up a local WebSocket server and broadcast mDNS
  Future<void> startBeacon(
    String roomId,
    Function(Map<String, dynamic>) onMessage,
  ) async {
    _onMessage = onMessage;

    // Bind to any available port
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    // Cascade HTTP Server running on port ${_server!.port}

    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        _socket = await WebSocketTransformer.upgrade(request);
        _isConnected = true;
        _socket!.listen(
          (data) {
            if (_onMessage != null) {
              _onMessage!(jsonDecode(data));
            }
          },
          onDone: () => _isConnected = false,
          onError: (e) => _isConnected = false,
        );
      } else {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.close();
      }
    });

    // Broadcast mDNS Service
    _registration = await nsd.register(
      nsd.Service(
        name: 'vapor_$roomId',
        type: '_vapor._tcp',
        port: _server!.port,
      ),
    );
    // Cascade mDNS Beacon Active: vapor_$roomId
  }

  // RECEIVER (Client): Scan mDNS for the specific room and connect via WebSocket
  Future<bool> scanAndConnect(
    String roomId,
    Function(Map<String, dynamic>) onMessage,
  ) async {
    _onMessage = onMessage;
    bool connected = false;

    try {
      _discovery = await nsd.startDiscovery('_vapor._tcp');

      final completer = Completer<bool>();

      _discovery!.addListener(() async {
        for (final service in _discovery!.services) {
          if (service.name == 'vapor_$roomId') {
            // Found the beacon!
            final ip = service.addresses?.first.address;
            final port = service.port;
            if (ip != null && port != null) {
              try {
                _socket = await WebSocket.connect('ws://$ip:$port');
                _isConnected = true;
                connected = true;

                _socket!.listen(
                  (data) {
                    if (_onMessage != null) {
                      _onMessage!(jsonDecode(data));
                    }
                  },
                  onDone: () => _isConnected = false,
                  onError: (e) => _isConnected = false,
                );

                if (!completer.isCompleted) completer.complete(true);
              } catch (e) {
                // Cascade WebSocket connection failed
              }
            }
          }
        }
      });

      // Wait max 2 seconds for local discovery
      await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 2), () {
          if (!completer.isCompleted) completer.complete(false);
        }),
      ]);

      await nsd.stopDiscovery(_discovery!);
      return connected;
    } catch (e) {
      // Cascade Discovery Error
      return false;
    }
  }

  void sendMessage(Map<String, dynamic> msg) {
    if (_isConnected && _socket != null) {
      _socket!.add(jsonEncode(msg));
    }
  }

  Future<void> dispose() async {
    _isConnected = false;
    if (_registration != null) {
      await nsd.unregister(_registration!);
      _registration = null;
    }
    if (_discovery != null) {
      await nsd.stopDiscovery(_discovery!);
      _discovery = null;
    }
    await _socket?.close();
    await _server?.close();
  }
}
