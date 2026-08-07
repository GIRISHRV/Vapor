import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'local_cascade.dart';

class SignalingEngine {
  final FirebaseDatabase database = FirebaseDatabase.instance;
  final String roomId;
  final String peerId;
  final LocalCascadeEngine _cascade = LocalCascadeEngine();

  Map<String, dynamic> _safeMapParse(dynamic value) {
    if (value == null) return {};
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    try {
      final jsonString = jsonEncode(value);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  StreamSubscription? _fbSdpSub;
  StreamSubscription? _fbIceSub;

  final StreamController<Map<String, dynamic>> _sdpController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _iceController =
      StreamController<Map<String, dynamic>>.broadcast();

  SignalingEngine({required this.roomId, required this.peerId}) {
    // Amnesiac: auto-purge room if client disconnects unexpectedly
    try {
      _roomRef.onDisconnect().remove();
    } catch (e) {
      // Ignore JS Interop errors on web for onDisconnect
    }
  }

  DatabaseReference get _roomRef => database.ref('rooms/$roomId');

  /// Initialize Cascade and Firebase Listeners
  Future<void> initialize({
    required bool isSender,
    required String remotePeerId,
  }) async {
    // Setup Cascade
    if (isSender) {
      await _cascade.startBeacon(roomId, _onCascadeMessage);
    } else {
      bool localConnected = await _cascade.scanAndConnect(
        roomId,
        _onCascadeMessage,
      );
      if (localConnected) {
        // Off-Grid Connection Established
      } else {
        // Local Discovery Failed
      }
    }

    // Setup Firebase listeners as fallback
    _fbSdpSub = _roomRef.child('sdp/$remotePeerId').onValue.listen((event) {
      if (event.snapshot.value != null) {
        _sdpController.add(_safeMapParse(event.snapshot.value));
      }
    });

    _fbIceSub = _roomRef.child('ice/$remotePeerId').onChildAdded.listen((
      event,
    ) {
      if (event.snapshot.value != null) {
        _iceController.add(_safeMapParse(event.snapshot.value));
      }
    });
  }

  void _onCascadeMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('sdp')) {
      _sdpController.add(msg['sdp']);
    } else if (msg.containsKey('ice')) {
      _iceController.add(msg['ice']);
    }
  }

  /// Post local SDP Offer or Answer
  Future<void> sendSdp(String type, String sdp) async {
    final payload = <String, dynamic>{'type': type, 'sdp': sdp};
    if (_cascade.isConnected) {
      _cascade.sendMessage(<String, dynamic>{'sdp': payload});
    }
    await _roomRef.child('sdp/$peerId').set(payload);
  }

  /// Post local ICE candidate
  Future<void> sendIceCandidate(Map<String, dynamic> candidate) async {
    if (_cascade.isConnected) {
      _cascade.sendMessage(<String, dynamic>{'ice': candidate});
    }
    await _roomRef.child('ice/$peerId').push().set(candidate);
  }

  /// Listen for remote SDP
  Stream<Map<String, dynamic>> listenForRemoteSdp(String remotePeerId) {
    return _sdpController.stream;
  }

  /// Listen for remote ICE candidates
  Stream<Map<String, dynamic>> listenForRemoteIceCandidates(
    String remotePeerId,
  ) {
    return _iceController.stream;
  }

  /// Purge the room completely
  Future<void> purgeRoom() async {
    await _roomRef.remove();
    await _fbSdpSub?.cancel();
    await _fbIceSub?.cancel();
    await _cascade.dispose();
  }
}
