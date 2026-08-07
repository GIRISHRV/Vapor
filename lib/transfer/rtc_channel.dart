import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../signaling/firebase.dart';

class RtcTransferEngine {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final SignalingEngine signaling;

  final List<RTCIceCandidate> _remoteIceCandidatesBuffer = [];
  bool _isRemoteDescriptionSet = false;

  // Callback when a chunk is received
  Function(Uint8List chunk)? onChunkReceived;
  // Callback when connection state changes
  Function(RTCPeerConnectionState state)? onStateChanged;
  // Callback when data channel opens
  Function()? onDataChannelOpen;

  RtcTransferEngine({required this.signaling});

  Future<void> initialize() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      signaling.sendIceCandidate({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onConnectionState = (state) {
      if (onStateChanged != null) onStateChanged!(state);
    };

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel();
    };
  }

  Future<void> createOffer() async {
    _dataChannel = await _peerConnection!.createDataChannel(
      'fileTransfer',
      RTCDataChannelInit()..ordered = true,
    );
    _setupDataChannel();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await signaling.sendSdp(offer.type!, offer.sdp!);
  }

  Future<void> handleRemoteSdp(Map<String, dynamic> sdpMap) async {
    final type = sdpMap['type'];
    final sdp = sdpMap['sdp'];
    if (type == null || sdp == null) return;

    final description = RTCSessionDescription(sdp, type);
    await _peerConnection!.setRemoteDescription(description);
    _isRemoteDescriptionSet = true;

    // Drain ICE candidate buffer
    for (var candidate in _remoteIceCandidatesBuffer) {
      await _peerConnection!.addCandidate(candidate);
    }
    _remoteIceCandidatesBuffer.clear();

    if (type == 'offer') {
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      await signaling.sendSdp(answer.type!, answer.sdp!);
    }
  }

  Future<void> handleRemoteIce(Map<String, dynamic> iceMap) async {
    final candidate = RTCIceCandidate(
      iceMap['candidate'],
      iceMap['sdpMid'],
      iceMap['sdpMLineIndex'],
    );
    if (_isRemoteDescriptionSet) {
      await _peerConnection!.addCandidate(candidate);
    } else {
      _remoteIceCandidatesBuffer.add(candidate);
    }
  }

  void _setupDataChannel() {
    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          onDataChannelOpen != null) {
        onDataChannelOpen!();
      }
    };

    // If it's already open (sometimes it is on creation)
    if (_dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen &&
        onDataChannelOpen != null) {
      onDataChannelOpen!();
    }

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      if (!message.isBinary) return;
      if (onChunkReceived != null) {
        onChunkReceived!(message.binary);
      }
    };
  }

  Future<void> sendChunk(Uint8List chunk) async {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel is not open');
    }

    int retries = 0;
    while (true) {
      // Implement SCTP backpressure control (Strict 256KB threshold for Web compatibility)
      while ((_dataChannel!.bufferedAmount ?? 0) > 256 * 1024) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      try {
        await _dataChannel!.send(RTCDataChannelMessage.fromBinary(chunk));
        break; // Success
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('queue is full') ||
            errStr.contains('operationerror')) {
          retries++;
          if (retries > 1000) {
            throw Exception(
              'Data channel send queue is persistently full. Connection dead?',
            );
          }
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> close() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    await signaling.purgeRoom(); // Amnesiac purge
  }

  Future<String> getConnectionQuality() async {
    if (_peerConnection == null) return "Unknown";
    try {
      final stats = await _peerConnection!.getStats();
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
