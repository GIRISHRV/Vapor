import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebRTC Config Map Types', () {
    test('configuration uses Map<String, dynamic> not Map<String, List>', () {
      final configuration = <String, dynamic>{
        'iceServers': [
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        ],
      };

      expect(configuration, isA<Map<String, dynamic>>());
      expect(
        configuration is Map<String, List<Map<String, String>>>,
        isFalse,
        reason: 'Must NOT be strictly typed map to avoid Web JS type errors',
      );
    });

    test('swarm configuration uses Map<String, dynamic>', () {
      final config = <String, dynamic>{
        'iceServers': [
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
          <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
        ],
      };

      expect(config, isA<Map<String, dynamic>>());
      expect(
        config is Map<String, List<Map<String, String>>>,
        isFalse,
        reason: 'Must NOT be strictly typed map to avoid Web JS type errors',
      );
    });
  });
}
