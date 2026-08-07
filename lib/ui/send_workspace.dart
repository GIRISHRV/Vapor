import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:math';
import 'dart:io';

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../signaling/firebase.dart';
import '../transfer/rtc_channel.dart';
import '../transfer/chunker.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/ecdh.dart';
import '../crypto/inspector.dart';
import 'animations/radar_pulse.dart';
import 'animations/success_check.dart';
import '../main.dart';
import '../crypto/panic_engine.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:share_plus/share_plus.dart';

class SendWorkspaceScreen extends ConsumerStatefulWidget {
  const SendWorkspaceScreen({super.key});

  @override
  ConsumerState<SendWorkspaceScreen> createState() =>
      _SendWorkspaceScreenState();
}

class _SendWorkspaceScreenState extends ConsumerState<SendWorkspaceScreen> {
  bool _isGenerating = false;
  String? _shareCode;
  String? _fileName;

  SignalingEngine? _signaling;
  RtcTransferEngine? _rtcEngine;
  List<PlatformFile> _files = [];
  SimpleKeyPair? _localKeyPair;
  SecretKey? _sessionKey;
  bool _isWaitingForAccept = false;
  double _progress = 0.0;
  String? _inviteLink;
  int _resumeOffset = 0;
  StreamSubscription? _sdpSubscription;
  StreamSubscription? _iceSubscription;

  @override
  void dispose() {
    _sdpSubscription?.cancel();
    _iceSubscription?.cancel();
    _rtcEngine?.close();
    PanicEngine.clearTeardowns();
    WakelockPlus.disable();
    super.dispose();
  }

  void _resetState() {
    _sdpSubscription?.cancel();
    _iceSubscription?.cancel();
    _rtcEngine?.close();
    if (mounted) {
      setState(() {
        _shareCode = null;
        _inviteLink = null;
        _isGenerating = false;
        _fileName = null;
        _signaling = null;
        _rtcEngine = null;
        _files = [];
        _localKeyPair = null;
        _sessionKey = null;
        _isWaitingForAccept = false;
        _progress = 0.0;
        _sdpSubscription = null;
        _iceSubscription = null;
      });
    }
  }

  String _generateRandomCode() {
    final rand = Random();
    final p1 = rand.nextInt(900) + 100;
    final p2 = rand.nextInt(900) + 100;
    return '$p1-$p2';
  }

  Future<void> _pickAndGenerateCode() async {
    // 1. Pick Files
    if (!kIsWeb) AppState.ignoreNextResume = true;
    FilePickerResult? result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return; // User canceled

    // 2. Inspect magic bytes for security
    for (var file in result.files) {
      Uint8List? headerBytes;
      if (file.bytes != null) {
        headerBytes = file.bytes!.length >= 16
            ? file.bytes!.sublist(0, 16)
            : file.bytes!;
      } else if (!kIsWeb && file.path != null) {
        final f = File(file.path!);
        final raf = await f.open();
        headerBytes = await raf.read(16);
        await raf.close();
      }

      if (headerBytes != null) {
        try {
          SecurityInspector.inspectMagicBytes(headerBytes);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Security Blocked: ${file.name} - $e')),
            );
          }
          return;
        }
      }
    }

    setState(() {
      _files = result.files;
      _fileName = _files.length == 1
          ? _files.first.name
          : '${_files.length} files';
      _isGenerating = true;
    });

    try {
      final code = _generateRandomCode();
      final normalizedCode = code.replaceAll(RegExp(r'[^0-9]'), '');

      try {
        _localKeyPair = await generateECDHKeyPair();
      } catch (e) {
        throw Exception('generateECDHKeyPair failed: $e');
      }

      final pubKey = await _localKeyPair!.extractPublicKey();
      final pubBytes = await serializePublicKey(pubKey);
      final pkBase64 = base64UrlEncode(pubBytes);

      final exp = DateTime.now()
          .add(const Duration(minutes: 15))
          .millisecondsSinceEpoch;

      final link = 'vapor://room?code=$code&exp=$exp&pk=$pkBase64';

      try {
        _signaling = SignalingEngine(roomId: normalizedCode, peerId: 'sender');
      } catch (e) {
        throw Exception('SignalingEngine Constructor failed: $e');
      }

      try {
        await _signaling!.initialize(isSender: true, remotePeerId: 'receiver');
      } catch (e) {
        throw Exception('SignalingEngine initialize failed: $e');
      }

      try {
        _rtcEngine = RtcTransferEngine(signaling: _signaling!);
      } catch (e) {
        throw Exception('RtcTransferEngine Constructor failed: $e');
      }

      PanicEngine.registerTeardown(() async {
        _rtcEngine?.close();
        await _signaling?.purgeRoom();
      });

      _rtcEngine!.onStateChanged = (state) async {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          final quality = await _rtcEngine!.getConnectionQuality();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Peer connected via $quality! Securing channel...'),
              ),
            );
          }
        }
      };

      _rtcEngine!.onDataChannelOpen = () {
        if (mounted) {
          _sendECDHPublicKey();
        }
      };

      _rtcEngine!.onChunkReceived = (data) async {
        final type = data[0];
        final payload = data.sublist(1);
        if (type == 0x01) {
          final remotePub = deserializePublicKey(payload);
          final roomId = _shareCode!.replaceAll(RegExp(r'[^0-9]'), '');
          _sessionKey = await deriveSharedSecret(
            _localKeyPair!,
            remotePub,
            roomId,
          );
          
          final localPub = await _localKeyPair!.extractPublicKey();
          final localBytes = Uint8List.fromList(await serializePublicKey(localPub));
          final sas = _computeSAS(localBytes, payload);

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Verify Connection (Zero-Trust)'),
                content: Text(
                  'To ensure no one is eavesdropping, verify this code with the receiver:\n\n$sas',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                  textAlign: TextAlign.center,
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _rtcEngine?.close();
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text('Reject', style: TextStyle(color: Colors.red)),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Secure Channel Established! Sending metadata...'),
                        ),
                      );
                      _sendMetadata();
                    },
                    child: const Text('Looks Good'),
                  ),
                ],
              ),
            );
          }
        } else if (type == 0x04) {
          // Peer Accepted
          if (mounted) {
            setState(() {
              _isWaitingForAccept = false;
            });
            _streamFiles();
          }
        } else if (type == 0x06) {
          // RESUME_REQ
          final offsetStr = utf8.decode(payload);
          final offset = int.tryParse(offsetStr) ?? 0;
          if (offset > 0) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Resume requested from byte $offset')),
              );
            }
            _resumeOffset = offset;
            if (mounted) {
              setState(() {
                _isWaitingForAccept = false;
              });
              _streamFiles();
            }
          }
        } else if (type == 0x05) {
          // Peer Rejected
          if (mounted) {
            setState(() {
              _isWaitingForAccept = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Peer rejected the transfer.')),
            );
            _rtcEngine?.close();
            setState(() {
              _shareCode = null;
            });
          }
        }
      };

      try {
        await _rtcEngine!.initialize();
      } catch (e) {
        throw Exception('rtcEngine.initialize failed: $e');
      }

      try {
        await _rtcEngine!.createOffer();
      } catch (e) {
        throw Exception('rtcEngine.createOffer failed: $e');
      }

      // Listen for Answer
      _sdpSubscription = _signaling!.listenForRemoteSdp('receiver').listen((
        sdpMap,
      ) {
        if (sdpMap.isNotEmpty) {
          _rtcEngine!.handleRemoteSdp(sdpMap);
        }
      });

      _iceSubscription = _signaling!
          .listenForRemoteIceCandidates('receiver')
          .listen((iceMap) {
            if (iceMap.isNotEmpty) {
              _rtcEngine!.handleRemoteIce(iceMap);
            }
          });

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _shareCode = code;
          _inviteLink = link;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Setup Failed: $e. Did you configure Firebase?'),
          ),
        );
      }
    }
  }

  Future<void> _sendECDHPublicKey() async {
    final pubKey = await _localKeyPair!.extractPublicKey();
    final pubBytes = await serializePublicKey(pubKey);
    final payload = Uint8List.fromList([0x01, ...pubBytes]);
    await _rtcEngine!.sendChunk(payload);
  }

  Future<void> _sendMetadata() async {
    if (_files.isEmpty || _sessionKey == null || _rtcEngine == null) return;

    setState(() {
      _isWaitingForAccept = true;
    });

    try {
      // Send metadata first (Type 0x02) - JSON Array
      final manifest = _files
          .map((f) => {'name': f.name, 'size': f.size})
          .toList();
      final metadata = jsonEncode(manifest);
      final metaChunk = await encryptChunk(utf8.encode(metadata), _sessionKey!);
      await _rtcEngine!.sendChunk(
        Uint8List.fromList([0x02, ...metaChunk.nonce, ...metaChunk.ciphertext]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Metadata Error: $e')));
        setState(() {
          _isWaitingForAccept = false;
        });
      }
    }
  }

  Future<void> _streamFiles() async {
    if (_files.isEmpty || _sessionKey == null || _rtcEngine == null) return;

    setState(() {
      _progress = 0.0;
    });
    WakelockPlus.enable();

    try {
      int totalBytes = _files.fold(0, (sum, f) => sum + f.size);
      int bytesSent = 0;

      for (int i = 0; i < _files.length; i++) {
        var file = _files[i];
        if (i > 0) {
          await _rtcEngine!.sendChunk(Uint8List.fromList([0x0A]));
        }

        if (!kIsWeb && file.path != null) {
          // Stream from disk
          await for (var chunk in FileChunker.streamFile(
            File(file.path!),
            resumeOffset: _resumeOffset,
          )) {
            final encrypted = await encryptChunk(chunk, _sessionKey!);
            final payload = Uint8List.fromList([
              0x03,
              ...encrypted.nonce,
              ...encrypted.ciphertext,
            ]);
            await _rtcEngine!.sendChunk(payload);

            bytesSent += chunk.length;
            if (!mounted) return;
            setState(() {
              _progress = bytesSent / totalBytes;
            });
          }
        } else if (file.bytes != null) {
          // Stream from memory (Web)
          int offset = _resumeOffset;
          while (offset < file.bytes!.length) {
            final end = min(offset + FileChunker.chunkSize, file.bytes!.length);
            final chunk = file.bytes!.sublist(offset, end);

            final encrypted = await encryptChunk(chunk, _sessionKey!);
            final payload = Uint8List.fromList([
              0x03,
              ...encrypted.nonce,
              ...encrypted.ciphertext,
            ]);
            await _rtcEngine!.sendChunk(payload);

            offset = end;
            bytesSent += chunk.length;
            if (!mounted) return;
            setState(() {
              _progress = bytesSent / totalBytes;
            });
          }
        }
        // Reset resume offset for the next file
        _resumeOffset = 0;
      }

      await _rtcEngine!.sendChunk(Uint8List.fromList([0x09]));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Transfer Complete!')));
        setState(() {
          _progress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Transfer Error: $e')));
        setState(() {});
      }
    } finally {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Workspace')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.1),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _shareCode == null
                ? _buildInitialState()
                : _buildActiveState(),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return DropTarget(
      onDragDone: (details) async {
        if (details.files.isNotEmpty) {
          // Wrap XFile in PlatformFile
          _files = details.files
              .map(
                (xfile) => PlatformFile(
                  name: xfile.name,
                  size:
                      0, // Cannot easily get size synchronously from XFile cross-platform, but FilePicker does. We'll use file path for native.
                  path: xfile.path,
                ),
              )
              .toList();

          if (!kIsWeb) {
            // Update sizes for native files
            for (var i = 0; i < _files.length; i++) {
              final f = File(_files[i].path!);
              _files[i] = PlatformFile(
                name: _files[i].name,
                size: f.lengthSync(),
                path: _files[i].path,
              );
            }
          } else {
            // Web handles bytes asynchronously, desktop_drop provides readAsBytes
            for (var i = 0; i < details.files.length; i++) {
              final bytes = await details.files[i].readAsBytes();
              _files[i] = PlatformFile(
                name: _files[i].name,
                size: bytes.length,
                bytes: bytes,
              );
            }
          }
          await _pickAndGenerateCode();
        }
      },
      child: Card(
        elevation: 4,
        shadowColor: Theme.of(
          context,
        ).colorScheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            key: const ValueKey('initial'),
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'send_icon',
                child: Icon(
                  Icons.description,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Select a file or drop it here to securely share with a peer.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (_isGenerating)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Processing file and connecting to swarm...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              else
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _pickAndGenerateCode,
                    icon: const Icon(Icons.file_upload),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text(
                        'Pick File & Generate Code',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveState() {
    final bool isConnected = _sessionKey != null;

    return SingleChildScrollView(
      child: Column(
        key: const ValueKey('active'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: 'send_icon',
            child: Icon(
              isConnected ? Icons.swap_horiz : Icons.qr_code,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 8,
            shadowColor: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: 0.3),
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_fileName != null)
                    Text(
                      'Sending: $_fileName',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 24),

                  if (!isConnected) ...[
                    // WAITING STATE
                    Text(
                      'Your Secure Code',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: PulsingRadar(
                        color: Theme.of(context).colorScheme.primary,
                        child: QrImageView(
                          data: _shareCode!,
                          version: QrVersions.auto,
                          size: 200.0,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _shareCode!,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 12,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () async {
                        final uriString = _inviteLink!;
                        if (kIsWeb) {
                          await Clipboard.setData(
                            ClipboardData(text: uriString),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Link copied to clipboard!'),
                              ),
                            );
                          }
                        } else {
                          AppState.ignoreNextResume = true;
                          // ignore: deprecated_member_use
                          Share.shareUri(Uri.parse(uriString));
                        }
                      },
                      icon: Icon(kIsWeb ? Icons.copy : Icons.share),
                      label: Text(
                        kIsWeb ? 'Copy Invite Link' : 'Share Invite Link',
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      'Waiting for peer to connect...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (_progress == 1.0) ...[
                    // COMPLETE STATE
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SuccessCheckmark(
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Transfer Complete',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _resetState,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Send Another File'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ] else ...[
                    // TRANSFERRING / WAITING FOR ACCEPT STATE
                    LinearProgressIndicator(
                      value: _progress,
                      borderRadius: BorderRadius.circular(8),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${(_progress * 100).toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isWaitingForAccept
                          ? 'Waiting for peer to accept files...'
                          : 'Sending data...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  String _computeSAS(Uint8List a, Uint8List b) {
    final list = [a, b];
    list.sort((x, y) {
      for (int i = 0; i < x.length && i < y.length; i++) {
        if (x[i] != y[i]) return x[i].compareTo(y[i]);
      }
      return x.length.compareTo(y.length);
    });
    final combined = Uint8List.fromList([...list[0], ...list[1]]);
    final hash = sha256.convert(combined).bytes;
    final sas = ((hash[0] << 8) | hash[1]) % 10000;
    return sas.toString().padLeft(4, '0');
  }
}
