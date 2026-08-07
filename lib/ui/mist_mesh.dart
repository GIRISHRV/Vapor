import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

import '../storage/web_saver.dart';
import '../transfer/mist_manager.dart';
import '../transfer/chunker.dart';
import '../main.dart';
import '../crypto/panic_engine.dart';
import '../crypto/merkle_tree.dart';
import 'components/vapor_components.dart';

class ChatMessage {
  final String sender;
  final String text;
  final String? fileId;
  final String? fileName;
  final int? fileSize;
  final bool isSystem;

  ChatMessage({
    required this.sender,
    required this.text,
    this.fileId,
    this.fileName,
    this.fileSize,
    this.isSystem = false,
  });
}

class HostedFile {
  final String id;
  final String name;
  final int size;
  final Uint8List? data; // for web
  final String? path; // for native
  final MerkleTree tree;

  HostedFile({
    required this.id,
    required this.name,
    required this.size,
    required this.tree,
    this.data,
    this.path,
  });
}

class IncomingFile {
  String id;
  String name;
  int totalSize;
  int totalChunks;
  Uint8List rootHash;
  Map<int, Uint8List> chunks = {};

  IncomingFile({
    required this.id,
    required this.name,
    required this.totalSize,
    required this.totalChunks,
    required this.rootHash,
  });

  int get receivedSize => chunks.values.fold(0, (sum, c) => sum + c.length);
}

class MistMeshScreen extends ConsumerStatefulWidget {
  const MistMeshScreen({super.key});

  @override
  ConsumerState<MistMeshScreen> createState() => _MistMeshScreenState();
}

class _MistMeshScreenState extends ConsumerState<MistMeshScreen> {
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isInMist = false;
  String? _roomId; // Hashed for network
  String? _mistKey; // Raw for UI display
  late String _localPeerId;
  MistManager? _mistManager;

  final List<String> _connectedPeers = [];
  final List<ChatMessage> _messages = [];

  // Files this node is seeding (available in memory)
  final Map<String, HostedFile> _hostedFiles = {};

  // Files currently being downloaded
  final Map<String, IncomingFile> _incomingFiles = {};

  StreamSubscription? _peerSubscription;
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();
    _localPeerId = 'peer_${Random().nextInt(90000) + 10000}';
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _peerSubscription?.cancel();
    _mistManager?.dispose();
    _roomController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    _hostedFiles.clear();
    _incomingFiles.clear();
    PanicEngine.clearTeardowns();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _joinMist() async {
    final inputKey = _roomController.text.trim();
    if (inputKey.isEmpty) return;

    // Zero-Trust Hashing: Create the invisible Firebase Room ID
    final digest = sha256.convert(utf8.encode(inputKey));
    final hashedRoomId = digest.toString();

    setState(() {
      _roomId = hashedRoomId;
      _mistKey = inputKey;
      _isInMist = true;
      _messages.add(
        ChatMessage(
          sender: 'System',
          text: 'Joining mist as $_localPeerId...',
          isSystem: true,
        ),
      );
    });

    // Pass the hashed Room ID to Mist Manager
    _mistManager = MistManager(
      roomId: hashedRoomId,
      localPeerId: _localPeerId,
    );

    PanicEngine.registerTeardown(() async {
      _mistManager?.dispose();
    });

    // Wire the GLOBAL data handler BEFORE joining
    _mistManager!.onDataReceived = (peerId, chunk) {
      _handleMistData(peerId, chunk);
    };

    _peerSubscription = _mistManager!.onPeerConnected.listen((peer) {
      if (mounted) {
        setState(() {
          if (!_connectedPeers.contains(peer.peerId)) {
            _connectedPeers.add(peer.peerId);
          }
          _messages.add(
            ChatMessage(
              sender: 'System',
              text: '${peer.peerId} connected!',
              isSystem: true,
            ),
          );
        });
        _scrollToBottom();
      }
    });

    _hudTimer?.cancel();
    _hudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isInMist) {
        setState(() {}); // Refresh Topology HUD
      }
    });

    await _mistManager!.joinMist();
  }

  void _handleMistData(String peerId, Uint8List chunk) {
    if (chunk.isEmpty) return;
    final type = chunk[0];
    final payload = chunk.sublist(1);

    if (type == 0x04) {
      // Text chat
      final msg = utf8.decode(payload);
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(sender: peerId, text: msg));
        });
        _scrollToBottom();
      }
    } else if (type == 0x05) {
      // File Offer
      try {
        final meta = jsonDecode(utf8.decode(payload));
        if (mounted) {
          setState(() {
            _messages.add(
              ChatMessage(
                sender: peerId,
                text: 'Shared a file',
                fileId: meta['id'],
                fileName: meta['name'],
                fileSize: meta['size'],
              ),
            );

            // Automatically start downloading if we don't have it
            _incomingFiles[meta['id']] = IncomingFile(
              id: meta['id'],
              name: meta['name'],
              totalSize: meta['size'],
              totalChunks: meta['totalChunks'],
              rootHash: base64Decode(meta['rootHash']),
            );
          });
          _scrollToBottom();

          // Request file automatically!
          _requestFile(meta['id'], meta['name'], meta['size']);
        }
      } catch (_) {}
    } else if (type == 0x07) {
      // Stream Request — someone wants a file from us
      try {
        final req = jsonDecode(utf8.decode(payload));
        final fileId = req['id'];
        final requester = req['requester'];

        if (_hostedFiles.containsKey(fileId)) {
          _streamFileToPeer(requester, _hostedFiles[fileId]!);
        }
      } catch (_) {}
    } else if (type == 0x06) {
      // File Chunk: [0x06, jsonLen (2 bytes), jsonBytes, chunkData]
      if (payload.length < 2) return;
      final jsonLen = ByteData.sublistView(payload).getUint16(0);
      if (payload.length < 2 + jsonLen) return;

      final headerStr = utf8.decode(payload.sublist(2, 2 + jsonLen));
      final chunkData = payload.sublist(2 + jsonLen);

      final header = jsonDecode(headerStr);
      _handleIncomingChunk(
        header['fileId'],
        header['index'],
        (header['proof'] as List)
            .map((p) => base64Decode(p as String))
            .toList(),
        chunkData,
        peerId,
      );
    }
  }

  void _leaveMist() {
    _hudTimer?.cancel();
    _mistManager?.dispose();
    _mistManager = null;
    setState(() {
      _isInMist = false;
      _roomId = null;
      _connectedPeers.clear();
      _messages.clear();
      _hostedFiles.clear();
      _incomingFiles.clear();
      _roomController.clear();
    });
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || _mistManager == null) return;

    final payload = Uint8List.fromList([0x04, ...utf8.encode(text)]);
    _mistManager!.broadcastMessage(payload);

    setState(() {
      _messages.add(ChatMessage(sender: 'Me', text: text));
      _chatController.clear();
    });
    _scrollToBottom();
  }

  Future<void> _broadcastFile() async {
    if (!kIsWeb) AppState.ignoreNextResume = true;
    FilePickerResult? result = await FilePicker.pickFiles(withData: kIsWeb);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    final fileId =
        'file_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';

    // Generate Merkle Tree
    final leafHashes = <Uint8List>[];
    int totalChunks = 0;

    if (kIsWeb && file.bytes != null) {
      final chunks = _generateChunks(file.bytes!);
      totalChunks = chunks.length;
      leafHashes.addAll(
        chunks.map((c) => Uint8List.fromList(sha256.convert(c).bytes)),
      );
    } else if (!kIsWeb && file.path != null) {
      await for (var chunk in FileChunker.streamFile(File(file.path!))) {
        totalChunks++;
        leafHashes.add(Uint8List.fromList(sha256.convert(chunk).bytes));
      }
    }

    final tree = MerkleTree.build(leafHashes);

    setState(() {
      _hostedFiles[fileId] = HostedFile(
        id: fileId,
        name: file.name,
        size: file.size,
        tree: tree,
        data: file.bytes,
        path: file.path,
      );
    });

    final meta = jsonEncode({
      'id': fileId,
      'name': file.name,
      'size': file.size,
      'totalChunks': totalChunks,
      'rootHash': base64Encode(tree.root),
    });

    _mistManager!.broadcastMessage(
      Uint8List.fromList([0x05, ...utf8.encode(meta)]),
    );

    setState(() {
      _messages.add(
        ChatMessage(
          sender: 'Me',
          text: 'Shared a file',
          fileId: fileId,
          fileName: file.name,
          fileSize: file.size,
        ),
      );
    });
    _scrollToBottom();
  }

  void _requestFile(String fileId, String fileName, int fileSize) {
    if (_hostedFiles.containsKey(fileId)) return;

    final req = jsonEncode({'id': fileId, 'requester': _localPeerId});
    _mistManager!.broadcastMessage(
      Uint8List.fromList([0x07, ...utf8.encode(req)]),
    );
  }

  List<Uint8List> _generateChunks(Uint8List data) {
    List<Uint8List> chunks = [];
    int offset = 0;
    while (offset < data.length) {
      final end = min(offset + 64 * 1024, data.length);
      chunks.add(data.sublist(offset, end));
      offset = end;
    }
    return chunks;
  }

  Future<void> _streamFileToPeer(String peerId, HostedFile file) async {
    int i = 0;
    Future<void> processChunk(Uint8List chunkData) async {
      final proof = file.tree.getProof(i).map((p) => base64Encode(p)).toList();

      final headerStr = jsonEncode({
        'fileId': file.id,
        'index': i,
        'proof': proof,
      });

      final headerBytes = utf8.encode(headerStr);
      final packet = Uint8List(1 + 2 + headerBytes.length + chunkData.length);
      packet[0] = 0x06;
      ByteData.sublistView(packet).setUint16(1, headerBytes.length);
      packet.setRange(3, 3 + headerBytes.length, headerBytes);
      packet.setRange(3 + headerBytes.length, packet.length, chunkData);

      _mistManager!.sendToPeer(peerId, packet);
      await Future.delayed(const Duration(milliseconds: 5));
      i++;
    }

    if (file.data != null) {
      final chunks = _generateChunks(file.data!);
      for (var chunkData in chunks) {
        await processChunk(chunkData);
      }
    } else if (file.path != null) {
      await for (var chunk in FileChunker.streamFile(File(file.path!))) {
        await processChunk(Uint8List.fromList(chunk));
      }
    }
  }

  Future<void> _handleIncomingChunk(
    String fileId,
    int index,
    List<Uint8List> proof,
    Uint8List chunkData,
    String senderPeerId,
  ) async {
    if (!_incomingFiles.containsKey(fileId)) return;
    final incoming = _incomingFiles[fileId]!;

    // Check if we already have this chunk (Gossip deduplication)
    if (incoming.chunks.containsKey(index)) return;

    // VERIFY MERKLE PROOF!
    final isValid = MerkleTree.verify(
      chunkData,
      index,
      proof,
      incoming.rootHash,
    );
    if (!isValid) {
      debugPrint("MERKLE VERIFICATION FAILED FOR CHUNK $index! DROPPING.");
      return;
    }

    // Valid chunk, save it!
    incoming.chunks[index] = chunkData;

    // GOSSIP FORWARD: Rebroadcast the validated chunk to the rest of the Mist (Tree Routing)
    final headerStr = jsonEncode({
      'fileId': fileId,
      'index': index,
      'proof': proof.map((p) => base64Encode(p)).toList(),
    });
    final headerBytes = utf8.encode(headerStr);
    final packet = Uint8List(1 + 2 + headerBytes.length + chunkData.length);
    packet[0] = 0x06;
    ByteData.sublistView(packet).setUint16(1, headerBytes.length);
    packet.setRange(3, 3 + headerBytes.length, headerBytes);
    packet.setRange(3 + headerBytes.length, packet.length, chunkData);

    // Broadcast to everyone (MistManager automatically sends only to connected peers)
    _mistManager!.broadcastMessage(packet, excludePeerId: senderPeerId);

    if (incoming.chunks.length % 10 == 0 ||
        incoming.chunks.length == incoming.totalChunks) {
      if (mounted) setState(() {});
    }

    if (incoming.chunks.length == incoming.totalChunks) {
      final BytesBuilder builder = BytesBuilder();
      final leafHashes = <Uint8List>[];
      for (int i = 0; i < incoming.totalChunks; i++) {
        final c = incoming.chunks[i]!;
        builder.add(c);
        leafHashes.add(Uint8List.fromList(sha256.convert(c).bytes));
      }
      final tree = MerkleTree.build(leafHashes);
      final fileBytes = builder.toBytes();

      String? path;
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        final tempFile = File('${dir.path}/vapor_mist_${incoming.id}');
        await tempFile.writeAsBytes(fileBytes);
        path = tempFile.path;

        PanicEngine.registerTeardown(() async {
          if (tempFile.existsSync()) tempFile.deleteSync();
        });
      }

      _hostedFiles[fileId] = HostedFile(
        id: fileId,
        name: incoming.name,
        size: incoming.totalSize,
        tree: tree,
        data: kIsWeb ? fileBytes : null,
        path: path,
      );
      _incomingFiles.remove(fileId);

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              sender: 'System',
              text: 'Finished downloading ${incoming.name}! (Merkle Verified)',
              isSystem: true,
            ),
          );
        });
        _scrollToBottom();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloaded ${incoming.name} (${fileBytes.length} bytes)',
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveFile(HostedFile file) async {
    if (kIsWeb) {
      if (file.data != null) {
        saveFileOnWeb(file.name, file.data!);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('File saved: ${file.name}')));
        }
      }
      return;
    }

    if (!kIsWeb) AppState.ignoreNextResume = true;
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save File',
      fileName: file.name,
    );

    if (outputFile != null) {
      try {
        if (file.data != null) {
          final f = File(outputFile);
          await f.writeAsBytes(file.data!);
        } else if (file.path != null) {
          final src = File(file.path!);
          await src.copy(outputFile);
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Saved to $outputFile')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: _isInMist ? _buildMistActive() : _buildJoinSetup(),
    );
  }

  Widget _buildJoinSetup() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: VaporCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hub,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Group Share',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: VaporButton(
                    onPressed: () {
                      _roomController.text =
                          '${Random().nextInt(900) + 100}-${Random().nextInt(900) + 100}-${Random().nextInt(900) + 100}';
                      _joinMist();
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add),
                        SizedBox(width: 8),
                        Text(
                          'Create Group',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Colors.grey)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                VaporTextField(
                  controller: _roomController,
                  placeholder: 'Enter Group ID',
                  prefix: const Icon(Icons.group_work),
                  inputFormatters: [MistCodeFormatter()],
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: VaporButton(
                    isPrimary: false,
                    onPressed: () {
                      if (_roomController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a Group ID'),
                          ),
                        );
                        return;
                      }
                      _joinMist();
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.login),
                        SizedBox(width: 8),
                        Text('Join Group'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMistActive() {
    return Column(
      children: [
        VaporCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.hub, size: 20),
              const SizedBox(width: 8),
              Text(
                'Mist: ${_mistKey ?? ""}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(kIsWeb ? Icons.copy : Icons.share, size: 16),
                tooltip: kIsWeb ? 'Copy Link' : 'Share',
                onPressed: () {
                  if (_mistKey != null) {
                    final expiry = DateTime.now()
                        .add(const Duration(minutes: 15))
                        .millisecondsSinceEpoch;
                    final hmac = Hmac(
                      sha256,
                      utf8.encode('vapor_ephemeral_salt_$_roomId'),
                    );
                    final sig = hmac
                        .convert(utf8.encode('$_mistKey:$expiry'))
                        .toString()
                        .substring(0, 16);
                    final link =
                        'https://vapor-engine.web.app/mist/$_mistKey?expires=$expiry&sig=$sig';
                    final shareText = 'Mist ID: $_mistKey\n\nJoin my secure Vapor mist! (Link self-destructs in 15m)\n\n$link';
                    
                    if (kIsWeb) {
                      Clipboard.setData(ClipboardData(text: shareText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied to clipboard!')),
                      );
                    } else {
                      AppState.ignoreNextResume = true;
                      // ignore: deprecated_member_use
                      Share.share(shareText);
                    }
                  }
                },
              ),
              const Spacer(),
              Text(
                'Peers: ${_connectedPeers.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'Leave Mist',
                color: Colors.redAccent,
                onPressed: _leaveMist,
              ),
            ],
          ),
        ),
        _buildTopologyHUD(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _buildChatMessage(_messages[index]);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              Expanded(
                child: VaporTextField(
                  controller: _chatController,
                  placeholder: 'Broadcast a message...',
                  onChanged: (val) {
                     // Add simple enter detection or rely on send button
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _broadcastFile,
                icon: const Icon(Icons.attach_file),
                tooltip: 'Broadcast File',
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopologyHUD() {
    if (_mistManager == null || _mistManager!.peers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _mistManager!.peers.length,
        itemBuilder: (context, index) {
          final peerId = _mistManager!.peers.keys.elementAt(index);
          final peer = _mistManager!.peers[peerId]!;

          return VaporCard(
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.all(12),
              width: 140,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    peerId,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi,
                        size: 14,
                        color: _getLatencyColor(peer.latencyMs),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        peer.latencyMs > 5000
                            ? '-- ms'
                            : '${peer.latencyMs} ms',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    peer.isConnected ? 'Connected' : 'Connecting...',
                    style: TextStyle(
                      fontSize: 10,
                      color: peer.isConnected ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getLatencyColor(int latencyMs) {
    if (latencyMs < 100) return Colors.green;
    if (latencyMs < 300) return Colors.orange;
    return Colors.red;
  }

  Widget _buildChatMessage(ChatMessage msg) {
    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            msg.text,
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    final isMe = msg.sender == 'Me';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    msg.sender,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (msg.fileId == null)
                Text(
                  msg.text,
                  style: TextStyle(
                    color: isMe
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              if (msg.fileId != null) _buildFileCard(msg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(ChatMessage msg) {
    final fileId = msg.fileId!;
    final isSeeding = _hostedFiles.containsKey(fileId);
    final isDownloading = _incomingFiles.containsKey(fileId);
    final progress = isDownloading
        ? (_incomingFiles[fileId]!.receivedSize /
              _incomingFiles[fileId]!.totalSize)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insert_drive_file,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg.fileName ?? 'Unknown',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${((msg.fileSize ?? 0) / 1024).toStringAsFixed(1)} KB',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (isSeeding)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Available locally',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                VaporButton(
                  isPrimary: false,
                  onPressed: () => _saveFile(_hostedFiles[fileId]!),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.save, size: 16),
                      SizedBox(width: 8),
                      Text('Save'),
                    ],
                  ),
                ),
              ],
            )
          else if (isDownloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: VaporButton(
                onPressed: () =>
                    _requestFile(fileId, msg.fileName!, msg.fileSize!),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download, size: 18),
                    SizedBox(width: 8),
                    Text('Download'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
