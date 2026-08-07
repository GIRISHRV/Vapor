import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class SwarmPeer {
  final String peerId;
  RTCPeerConnection? peerConnection;
  final List<RTCDataChannel> dataChannels = [];
  int currentChannelIndex = 0;
  bool isConnected = false;
  int latencyMs = 999999;

  final List<RTCIceCandidate> _iceCandidateBuffer = [];
  bool _remoteDescriptionSet = false;

  SwarmPeer(this.peerId);

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    if (_remoteDescriptionSet && peerConnection != null) {
      await peerConnection!.addCandidate(candidate);
    } else {
      _iceCandidateBuffer.add(candidate);
    }
  }

  Future<void> drainIceCandidates() async {
    _remoteDescriptionSet = true;
    for (var c in _iceCandidateBuffer) {
      await peerConnection!.addCandidate(c);
    }
    _iceCandidateBuffer.clear();
  }

  Future<String> getConnectionQuality() async {
    if (peerConnection == null) return "Unknown";
    try {
      final stats = await peerConnection!.getStats();
      for (var report in stats) {
        if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
          final localCandidateId = report.values['localCandidateId'];
          for (var localReport in stats) {
            if (localReport.id == localCandidateId) {
              final type = localReport.values['candidateType'] ?? localReport.values['networkType'] ?? '';
              if (type.toString().contains('relay')) {
                return "☁️ Relayed (Cloud)";
              } else if (type.toString().contains('srflx') || type.toString().contains('prflx')) {
                return "🌐 Direct (Internet)";
              } else if (type.toString().contains('host')) {
                return "⚡ Direct (LAN)";
              }
            }
          }
        }
      }
    } catch (_) {}
    return "⚡ Direct (Unknown)";
  }
}

Map<String, dynamic> _safeMapParse(dynamic value) {
  if (value == null) return <String, dynamic>{};
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  try {
    final jsonString = jsonEncode(value);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (_) {
    return <String, dynamic>{};
  }
}

class SwarmManager {
  final String roomId;
  final String localPeerId;
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final Map<String, SwarmPeer> _peers = {};

  final StreamController<SwarmPeer> _onPeerConnected =
      StreamController.broadcast();
  Stream<SwarmPeer> get onPeerConnected => _onPeerConnected.stream;

  // Expose peer list for UI
  Map<String, SwarmPeer> get peers => Map.unmodifiable(_peers);

  // Global chunk handler — set by the UI before joining
  Function(String peerId, Uint8List chunk)? onDataReceived;

  final List<StreamSubscription> _subscriptions = [];

  SwarmManager({required this.roomId, required this.localPeerId});

  DatabaseReference get _roomRef => _db.ref('swarms/$roomId');

  Future<void> joinSwarm() async {
    // Announce presence
    await _roomRef.child('presence/$localPeerId').set({
      'joined': ServerValue.timestamp,
    });
    // Auto-remove on disconnect
    try {
      _roomRef.child('presence/$localPeerId').onDisconnect().remove();
    } catch (_) {}

    // Listen for other peers announcing presence
    _subscriptions.add(
      _roomRef.child('presence').onChildAdded.listen((event) {
        final remotePeerId = event.snapshot.key;
        if (remotePeerId == null || remotePeerId == localPeerId) return;
        if (_peers.containsKey(remotePeerId)) return;

        // Deterministic initiator: alphabetically first peer initiates
        final isInitiator = localPeerId.compareTo(remotePeerId) < 0;
        _initiatePeerConnection(remotePeerId, isInitiator);
      }),
    );

    // Listen for SDP offers/answers directed at us
    _subscriptions.add(
      _roomRef.child('sdp/$localPeerId').onChildAdded.listen((event) async {
        if (event.snapshot.value == null) return;
        final map = _safeMapParse(event.snapshot.value);
        final from = map['from'] as String?;
        final type = map['type'] as String?;
        final sdp = map['sdp'] as String?;
        if (from == null || type == null || sdp == null) return;

        final peer = _peers[from];
        if (peer == null || peer.peerConnection == null) return;

        final desc = RTCSessionDescription(sdp, type);

        if (type == 'offer') {
          await peer.peerConnection!.setRemoteDescription(desc);
          await peer.drainIceCandidates();

          final answer = await peer.peerConnection!.createAnswer();
          await peer.peerConnection!.setLocalDescription(answer);

          // Send answer back to the offerer
          await _roomRef.child('sdp/$from').push().set({
            'type': answer.type,
            'sdp': answer.sdp,
            'from': localPeerId,
          });
        } else if (type == 'answer') {
          await peer.peerConnection!.setRemoteDescription(desc);
          await peer.drainIceCandidates();
        }

        // Clean up this SDP entry after processing
        event.snapshot.ref.remove();
      }),
    );

    // Listen for ICE candidates directed at us
    _subscriptions.add(
      _roomRef.child('ice/$localPeerId').onChildAdded.listen((event) async {
        if (event.snapshot.value == null) return;
        final map = _safeMapParse(event.snapshot.value);
        final from = map['from'] as String?;
        if (from == null) return;

        final peer = _peers[from];
        if (peer == null) return;

        final candidate = RTCIceCandidate(
          map['candidate'],
          map['sdpMid'],
          map['sdpMLineIndex'],
        );
        await peer.addIceCandidate(candidate);

        // Clean up
        event.snapshot.ref.remove();
      }),
    );
  }

  Future<void> _initiatePeerConnection(
    String remotePeerId,
    bool isInitiator,
  ) async {
    final peer = SwarmPeer(remotePeerId);
    _peers[remotePeerId] = peer;

    final config = <String, dynamic>{
      'iceServers': [
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
      ],
    };

    peer.peerConnection = await createPeerConnection(config);

    // Wire ICE candidate forwarding
    peer.peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _roomRef.child('ice/$remotePeerId').push().set({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'from': localPeerId,
      });
    };

    // Wire connection state
    peer.peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (!peer.isConnected) {
          peer.isConnected = true;
          _onPeerConnected.add(peer);
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        peer.isConnected = false;
      }
    };

    peer.peerConnection!.onDataChannel = (channel) {
      peer.dataChannels.add(channel);
      _wireDataChannel(peer, channel);
    };

    if (isInitiator) {
      // Create multiplexed data channels BEFORE creating offer
      for (int i = 0; i < 4; i++) {
        final dc = await peer.peerConnection!.createDataChannel(
          'swarm_$i',
          RTCDataChannelInit()..ordered = true,
        );
        peer.dataChannels.add(dc);
        _wireDataChannel(peer, dc);
      }

      // Create and send offer
      final offer = await peer.peerConnection!.createOffer();
      await peer.peerConnection!.setLocalDescription(offer);

      await _roomRef.child('sdp/$remotePeerId').push().set({
        'type': offer.type,
        'sdp': offer.sdp,
        'from': localPeerId,
      });
    }
  }

  void _wireDataChannel(SwarmPeer peer, RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        if (!peer.isConnected) {
          peer.isConnected = true;
          _onPeerConnected.add(peer);
        }
        _sendPing(peer, channel);
      }
    };

    // Check if already open
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      if (!peer.isConnected) {
        peer.isConnected = true;
        _onPeerConnected.add(peer);
      }
    }

    channel.onMessage = (RTCDataChannelMessage message) {
      if (!message.isBinary) return;
      final bytes = message.binary;
      if (bytes.isEmpty) return;

      if (bytes[0] == 0x07) {
        // Ping
        channel.send(
          RTCDataChannelMessage.fromBinary(
            Uint8List.fromList([0x08, ...bytes.sublist(1)]),
          ),
        );
        return;
      } else if (bytes[0] == 0x08) {
        // Pong
        final sentTime = DateTime.fromMillisecondsSinceEpoch(
          ByteData.sublistView(bytes.sublist(1)).getFloat64(0).toInt(),
        );
        peer.latencyMs = DateTime.now().difference(sentTime).inMilliseconds;
        _evaluateAndCullConnections();
        return;
      }

      if (onDataReceived != null) {
        onDataReceived!(peer.peerId, bytes);
      }
    };
  }

  void _sendPing(SwarmPeer peer, RTCDataChannel channel) {
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      final bytes = Uint8List(9);
      bytes[0] = 0x07;
      ByteData.sublistView(
        bytes,
      ).setFloat64(1, DateTime.now().millisecondsSinceEpoch.toDouble());
      channel.send(RTCDataChannelMessage.fromBinary(bytes));
    }
  }

  // Adaptive Latency Mesh Configuration
  static const int targetPeers = 4;
  static const int maxPeers = 6;

  void _evaluateAndCullConnections() {
    if (_peers.length <= targetPeers) return;

    // Sort peers by latency (lowest first)
    final sortedPeers = _peers.values.toList()
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));

    // Cull the slowest peers until we reach targetPeers
    for (int i = targetPeers; i < sortedPeers.length; i++) {
      _disconnectPeer(sortedPeers[i].peerId);
    }
  }

  void _disconnectPeer(String peerId) {
    final peer = _peers[peerId];
    if (peer == null) return;
    for (var dc in peer.dataChannels) {
      dc.close();
    }
    peer.peerConnection?.close();
    peer.isConnected = false;
    _peers.remove(peerId);
  }

  void broadcastMessage(Uint8List payload, {String? excludePeerId}) {
    for (var peer in _peers.values) {
      if (peer.peerId == excludePeerId) continue;
      if (peer.isConnected && peer.dataChannels.isNotEmpty) {
        for (var dc in peer.dataChannels) {
          if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
            try {
              dc.send(RTCDataChannelMessage.fromBinary(payload));
            } catch (_) {}
          }
        }
      }
    }
  }

  void sendToPeer(String peerId, Uint8List payload) {
    final peer = _peers[peerId];
    if (peer != null && peer.isConnected && peer.dataChannels.isNotEmpty) {
      // Round Robin Multiplexing
      final dc = peer.dataChannels[peer.currentChannelIndex];
      peer.currentChannelIndex =
          (peer.currentChannelIndex + 1) % peer.dataChannels.length;

      if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          dc.send(RTCDataChannelMessage.fromBinary(payload));
        } catch (_) {}
      }
    }
  }

  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    for (var peer in _peers.values) {
      for (var dc in peer.dataChannels) {
        dc.close();
      }
      peer.peerConnection?.close();
    }
    _peers.clear();
    _roomRef.child('presence/$localPeerId').remove();
    _roomRef.child('sdp/$localPeerId').remove();
    _roomRef.child('ice/$localPeerId').remove();
    _onPeerConnected.close();
  }
}
