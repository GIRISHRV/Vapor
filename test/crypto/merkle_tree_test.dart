import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/crypto/merkle_tree.dart';

void main() {
  group('Merkle Tree Tests', () {
    Uint8List sha256Hash(List<int> input) {
      return Uint8List.fromList(sha256.convert(input).bytes);
    }

    test('build throws ArgumentError on empty leaf hashes', () {
      expect(() => MerkleTree.build([]), throwsArgumentError);
    });

    test('build works with single leaf hash', () {
      final leafHashes = [
        sha256Hash([1]),
      ];
      final tree = MerkleTree.build(leafHashes);

      expect(tree.levels.length, 1);
      expect(tree.root, leafHashes[0]);
    });

    test('build works with even number of leaf hashes', () {
      final leafHashes = [
        sha256Hash([1]),
        sha256Hash([2]),
        sha256Hash([3]),
        sha256Hash([4]),
      ];
      final tree = MerkleTree.build(leafHashes);

      expect(tree.levels.length, 3);
      expect(tree.levels[0].length, 4);
      expect(tree.levels[1].length, 2);
      expect(tree.levels[2].length, 1);
    });

    test('build works with odd number of leaf hashes', () {
      final leafHashes = [
        sha256Hash([1]),
        sha256Hash([2]),
        sha256Hash([3]),
      ];
      final tree = MerkleTree.build(leafHashes);

      // Node 3 is duplicated to pair with itself
      expect(tree.levels.length, 3);
      expect(tree.levels[0].length, 3);
      expect(tree.levels[1].length, 2);
      expect(tree.levels[2].length, 1);
    });

    test('verify should return true for valid proof', () {
      final chunks = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
        Uint8List.fromList([7, 8, 9]),
      ];

      final leafHashes = chunks.map((c) => sha256Hash(c)).toList();
      final tree = MerkleTree.build(leafHashes);

      for (int i = 0; i < chunks.length; i++) {
        final proof = tree.getProof(i);
        final isValid = MerkleTree.verify(chunks[i], i, proof, tree.root);
        expect(isValid, isTrue);
      }
    });

    test('verify should return false for tampered chunk', () {
      final chunks = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ];

      final leafHashes = chunks.map((c) => sha256Hash(c)).toList();
      final tree = MerkleTree.build(leafHashes);

      final proof = tree.getProof(0);

      // Tamper chunk
      final tamperedChunk = Uint8List.fromList([1, 2, 4]);
      final isValid = MerkleTree.verify(tamperedChunk, 0, proof, tree.root);
      expect(isValid, isFalse);
    });

    test('verify should return false for incorrect index', () {
      final chunks = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ];

      final leafHashes = chunks.map((c) => sha256Hash(c)).toList();
      final tree = MerkleTree.build(leafHashes);

      final proof = tree.getProof(0);

      // Verify with wrong index
      final isValid = MerkleTree.verify(chunks[0], 1, proof, tree.root);
      expect(isValid, isFalse);
    });

    test('verify should return false for tampered proof', () {
      final chunks = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5, 6]),
      ];

      final leafHashes = chunks.map((c) => sha256Hash(c)).toList();
      final tree = MerkleTree.build(leafHashes);

      // Tamper proof
      final tamperedProof = [
        sha256Hash([99]),
      ];
      final isValid = MerkleTree.verify(chunks[0], 0, tamperedProof, tree.root);
      expect(isValid, isFalse);
    });
  });
}
