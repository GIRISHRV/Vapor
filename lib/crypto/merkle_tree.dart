import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class MerkleTree {
  final List<List<Uint8List>> levels;

  MerkleTree._(this.levels);

  /// Get the root hash of the tree.
  Uint8List get root => levels.last.first;

  /// Generate a Merkle Tree from a list of chunk hashes.
  /// This should be run in an isolate for large files.
  static MerkleTree build(List<Uint8List> leafHashes) {
    if (leafHashes.isEmpty) {
      throw ArgumentError('Leaf hashes cannot be empty');
    }

    List<List<Uint8List>> levels = [leafHashes];
    List<Uint8List> currentLevel = leafHashes;

    while (currentLevel.length > 1) {
      List<Uint8List> nextLevel = [];
      for (int i = 0; i < currentLevel.length; i += 2) {
        if (i + 1 == currentLevel.length) {
          // Odd number of nodes, duplicate the last one
          nextLevel.add(_hashPair(currentLevel[i], currentLevel[i]));
        } else {
          nextLevel.add(_hashPair(currentLevel[i], currentLevel[i + 1]));
        }
      }
      levels.add(nextLevel);
      currentLevel = nextLevel;
    }

    return MerkleTree._(levels);
  }

  /// Generate a proof for a specific chunk index.
  /// The proof is a list of sibling hashes required to compute the root.
  List<Uint8List> getProof(int index) {
    List<Uint8List> proof = [];
    int currentIndex = index;

    for (int i = 0; i < levels.length - 1; i++) {
      int isRightNode = currentIndex % 2;
      int siblingIndex = (isRightNode == 1)
          ? currentIndex - 1
          : currentIndex + 1;

      if (siblingIndex < levels[i].length) {
        proof.add(levels[i][siblingIndex]);
      } else {
        // If the sibling index is out of bounds, it means this was an odd node that got duplicated
        proof.add(levels[i][currentIndex]);
      }
      currentIndex ~/= 2;
    }

    return proof;
  }

  /// Verify a chunk against a root hash using a proof.
  static bool verify(
    Uint8List chunk,
    int index,
    List<Uint8List> proof,
    Uint8List root,
  ) {
    Uint8List currentHash = Uint8List.fromList(sha256.convert(chunk).bytes);
    int currentIndex = index;

    for (int i = 0; i < proof.length; i++) {
      int isRightNode = currentIndex % 2;
      if (isRightNode == 1) {
        currentHash = _hashPair(proof[i], currentHash);
      } else {
        currentHash = _hashPair(currentHash, proof[i]);
      }
      currentIndex ~/= 2;
    }

    // Compare lists
    if (currentHash.length != root.length) return false;
    for (int i = 0; i < currentHash.length; i++) {
      if (currentHash[i] != root[i]) return false;
    }
    return true;
  }

  static Uint8List _hashPair(Uint8List left, Uint8List right) {
    final combined = Uint8List(left.length + right.length);
    combined.setAll(0, left);
    combined.setAll(left.length, right);
    return Uint8List.fromList(sha256.convert(combined).bytes);
  }
}
