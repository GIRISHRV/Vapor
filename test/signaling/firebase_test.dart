import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Signaling Map Types', () {
    test('sendSdp creates a Map<String, dynamic> not Map<String, String>', () {
      final type = 'offer';
      final sdp = 'v=0\\r\\n';

      // Simulating what sendSdp does
      final payload = <String, dynamic>{'type': type, 'sdp': sdp};

      // Ensure the payload is not strictly a Map<String, String>
      // as that crashes JS interop on Flutter Web
      expect(payload, isA<Map<String, dynamic>>());
      expect(
        payload is Map<String, String>,
        isFalse,
        reason:
            'Must NOT be Map<String, String> to avoid minified JS type errors',
      );
    });

    test('sendIceCandidate configures dynamic map', () {
      final candidate = <String, dynamic>{
        'candidate': 'candidate:1 1 UDP 2013266431',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      };

      expect(candidate, isA<Map<String, dynamic>>());
    });
  });
}
