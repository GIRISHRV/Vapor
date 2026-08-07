import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app/transfer/rtc_channel.dart';
import 'package:app/signaling/firebase.dart';
import 'dart:typed_data';
import 'dart:async';

// A mock signaling engine that forwards messages directly in-memory
// between the sender and receiver, completely bypassing Firebase and LocalCascade.
class MockSignalingEngine extends Fake implements SignalingEngine {
  MockSignalingEngine? peer;
  
  final StreamController<Map<String, dynamic>> _sdpController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _iceController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> listenForRemoteSdp(String remotePeerId) {
    return _sdpController.stream;
  }

  @override
  Stream<Map<String, dynamic>> listenForRemoteIceCandidates(String remotePeerId) {
    return _iceController.stream;
  }

  @override
  Future<void> sendSdp(String type, String sdp) async {
    // Send directly to peer's listener
    peer?._sdpController.add({'type': type, 'sdp': sdp});
  }

  @override
  Future<void> sendIceCandidate(Map<String, dynamic> candidate) async {
    // Send directly to peer's listener
    peer?._iceController.add(candidate);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-End P2P Transfer Logic', (WidgetTester tester) async {
    // 1. Setup in-memory signaling engines
    final senderSignaling = MockSignalingEngine();
    final receiverSignaling = MockSignalingEngine();
    
    // Cross-link them so they talk to each other
    senderSignaling.peer = receiverSignaling;
    receiverSignaling.peer = senderSignaling;

    // 2. Initialize engines
    final senderEngine = RtcTransferEngine(signaling: senderSignaling);
    final receiverEngine = RtcTransferEngine(signaling: receiverSignaling);

    await senderEngine.initialize();
    await receiverEngine.initialize();

    // 3. Setup completion checks
    bool senderChannelOpen = false;
    bool receiverChannelOpen = false;
    bool dataReceived = false;
    final completer = Completer<void>();

    senderEngine.onDataChannelOpen = () {
      senderChannelOpen = true;
      if (receiverChannelOpen) {
        // Channels are open, let's send some bytes
        senderEngine.sendChunk(Uint8List.fromList([1, 2, 3, 4, 42]));
      }
    };

    receiverEngine.onDataChannelOpen = () {
      receiverChannelOpen = true;
      if (senderChannelOpen) {
        senderEngine.sendChunk(Uint8List.fromList([1, 2, 3, 4, 42]));
      }
    };

    receiverEngine.onChunkReceived = (chunk) {
      if (chunk.length == 5 && chunk[4] == 42) {
        dataReceived = true;
        completer.complete();
      }
    };

    // 4. Start the WebRTC handshake
    // Sender creates offer, sends via signaling
    await senderEngine.createOffer();

    receiverSignaling.listenForRemoteSdp('sender').listen((data) async {
      await receiverEngine.handleRemoteSdp(data);
    });

    senderSignaling.listenForRemoteSdp('receiver').listen((data) async {
      await senderEngine.handleRemoteSdp(data);
    });

    receiverSignaling.listenForRemoteIceCandidates('sender').listen((data) {
      receiverEngine.handleRemoteIce(data);
    });

    senderSignaling.listenForRemoteIceCandidates('receiver').listen((data) {
      senderEngine.handleRemoteIce(data);
    });

    // 5. Wait for the chunk to travel across the WebRTC data channel
    // We'll give it a timeout of 5 seconds to establish connection and transmit.
    await completer.future.timeout(const Duration(seconds: 15));

    expect(senderChannelOpen, isTrue);
    expect(receiverChannelOpen, isTrue);
    expect(dataReceived, isTrue);
  });
}
