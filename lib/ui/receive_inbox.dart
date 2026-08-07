import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:io';
import 'dart:async';

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
// Removed file_picker
import 'package:crypto/crypto.dart';
import '../storage/web_saver.dart';
import '../signaling/firebase.dart';
import '../transfer/rtc_channel.dart';
import '../transfer/chunker.dart';
import '../crypto/aes_gcm.dart';
import '../crypto/ecdh.dart';
import '../crypto/inspector.dart';
import '../crypto/panic_engine.dart';
import 'animations/success_check.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReceiveInboxScreen extends ConsumerStatefulWidget {
  final String? initialCode;
  final Map<String, dynamic>? initialExtra;
  const ReceiveInboxScreen({super.key, this.initialCode, this.initialExtra});

  @override
  ConsumerState<ReceiveInboxScreen> createState() => _ReceiveInboxScreenState();
}

class TransferFile {
  final String name;
  final int size;
  int bytesReceived = 0;
  TransferFile(this.name, this.size);
}

class _ReceiveInboxScreenState extends ConsumerState<ReceiveInboxScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isConnecting = false;
  double _progress = 0.0;
  String _statusMessage = 'Waiting for peer to connect...';
  bool _isScanning = false;
  bool _isCompleted = false;

  SignalingEngine? _signaling;
  RtcTransferEngine? _rtcEngine;
  SimpleKeyPair? _localKeyPair;
  SecretKey? _sessionKey;

  StreamSubscription? _sdpSubscription;
  StreamSubscription? _iceSubscription;

  List<TransferFile> _manifest = [];
  int _currentFileIndex = 0;
  int _incomingFileSize = 0;
  int _bytesReceived = 0;
  File? _tempFile;
  final List<int> _webBuffer = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      _codeController.text = widget.initialCode!;

      if (widget.initialExtra != null && widget.initialExtra!['exp'] != null) {
        final expStr = widget.initialExtra!['exp'].toString();
        final exp = int.tryParse(expStr) ?? 0;
        if (DateTime.now().millisecondsSinceEpoch > exp) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Link Expired! Security block active.'),
                backgroundColor: Colors.red,
              ),
            );
          });
          return;
        }
      }

      // Delay slightly to let the widget mount fully before connecting
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _connectToPeer();
        }
      });
    }
  }

  @override
  void dispose() {
    _sdpSubscription?.cancel();
    _iceSubscription?.cancel();
    _rtcEngine?.close();
    _codeController.dispose();
    if (_tempFile != null && _tempFile!.existsSync()) {
      _tempFile!.deleteSync();
    }
    PanicEngine.clearTeardowns();
    WakelockPlus.disable();
    super.dispose();
  }

  String _computeSAS(List<int> a, List<int> b) {
    final list = [a, b];
    list.sort((x, y) {
      for (int i = 0; i < x.length && i < y.length; i++) {
        if (x[i] != y[i]) return x[i].compareTo(y[i]);
      }
      return x.length.compareTo(y.length);
    });
    final combined = [...list[0], ...list[1]];
    final hash = sha256.convert(combined).bytes;
    final sas = ((hash[0] << 8) | hash[1]) % 10000;
    return sas.toString().padLeft(4, '0');
  }

  void _resetState() {
    _sdpSubscription?.cancel();
    _iceSubscription?.cancel();
    _rtcEngine?.close();
    if (mounted) {
      setState(() {
        _codeController.clear();
        _isConnecting = false;
        _progress = 0.0;
        _statusMessage = 'Waiting for peer to connect...';
        _signaling = null;
        _rtcEngine = null;
        _sdpSubscription = null;
        _iceSubscription = null;
        _localKeyPair = null;
        _sessionKey = null;
        _manifest = [];
        _currentFileIndex = 0;
        _incomingFileSize = 0;
        _bytesReceived = 0;
        if (_tempFile != null && _tempFile!.existsSync()) {
          _tempFile!.deleteSync();
        }
        _tempFile = null;
        _webBuffer.clear();
      });
    }
    WakelockPlus.disable();
  }

  Future<void> _connectToPeer() async {
    final rawCode = _codeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawCode.length < 6) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      _signaling = SignalingEngine(roomId: rawCode, peerId: 'receiver');
      await _signaling!.initialize(isSender: false, remotePeerId: 'sender');
      _rtcEngine = RtcTransferEngine(signaling: _signaling!);

      PanicEngine.registerTeardown(() async {
        _rtcEngine?.close();
        await _signaling?.purgeRoom();
        WakelockPlus.disable();
      });

      _localKeyPair = await generateECDHKeyPair();

      _rtcEngine!.onStateChanged = (state) async {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          final quality = await _rtcEngine!.getConnectionQuality();
          if (mounted) {
            setState(() {
              _statusMessage = 'Connected ($quality)! Securing...';
            });
          }
        }
      };

      _rtcEngine!.onDataChannelOpen = () {
        if (mounted) {
          _sendECDHPublicKey();
        }
      };

      _rtcEngine!.onChunkReceived = _handleIncomingData;

      await _rtcEngine!.initialize();

      // Listen for Offer
      _sdpSubscription = _signaling!.listenForRemoteSdp('sender').listen((
        sdpMap,
      ) {
        if (sdpMap.isNotEmpty) {
          _rtcEngine!.handleRemoteSdp(sdpMap);
        }
      });

      _iceSubscription = _signaling!
          .listenForRemoteIceCandidates('sender')
          .listen((iceMap) {
            if (iceMap.isNotEmpty) {
              _rtcEngine!.handleRemoteIce(iceMap);
            }
          });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Transfer Failed: $e';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connection Failed: $e')));
      }
      WakelockPlus.disable();
    }
  }

  Future<void> _sendECDHPublicKey() async {
    if (_localKeyPair == null || _rtcEngine == null) return;
    final pubKey = await _localKeyPair!.extractPublicKey();
    final pubBytes = await serializePublicKey(pubKey);
    final payload = Uint8List.fromList([0x01, ...pubBytes]);
    await _rtcEngine!.sendChunk(payload);
  }

  Future<void> _prepareNextFile() async {
    if (_currentFileIndex >= _manifest.length) return;
    final currentFile = _manifest[_currentFileIndex];
    if (!kIsWeb) {
      final tempDir = await getTemporaryDirectory();
      _tempFile = File('${tempDir.path}/${currentFile.name}');
      if (_tempFile!.existsSync() && currentFile.bytesReceived == 0) {
        _tempFile!.deleteSync();
      }
    } else {
      if (currentFile.bytesReceived == 0) _webBuffer.clear();
    }
  }

  void _downloadCurrentFile() {
    final currentFile = _manifest[_currentFileIndex];
    if (kIsWeb) {
      saveFileOnWeb(currentFile.name, Uint8List.fromList(_webBuffer));
    } else if (_tempFile != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File downloaded to: ${_tempFile!.path}')),
      );
    }
  }

  Future<void> _handleIncomingData(Uint8List data) async {
    if (data.isEmpty) return;
    final type = data[0];
    final payload = data.sublist(1);

    if (type == 0x01) {
      // ECDH Public Key
      final remotePub = deserializePublicKey(payload);
      final roomId = _codeController.text.replaceAll(RegExp(r'[^0-9]'), '');
      _sessionKey = await deriveSharedSecret(_localKeyPair!, remotePub, roomId);
      
      final localPub = await _localKeyPair!.extractPublicKey();
      final localBytes = await serializePublicKey(localPub);
      final sas = _computeSAS(localBytes, payload);

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Verify Connection (Zero-Trust)'),
            content: Text(
              'To ensure no one is eavesdropping, verify this code with the sender:\n\n$sas',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _rtcEngine?.close();
                  if (mounted) {
                    setState(() { _isConnecting = false; _statusMessage = 'Connection rejected.'; });
                  }
                },
                child: const Text('Reject', style: TextStyle(color: Colors.red)),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (mounted) {
                    setState(() { _statusMessage = 'Secure Channel Established. Waiting...'; });
                  }
                },
                child: const Text('Looks Good'),
              ),
            ],
          ),
        );
      }
    } else if (type == 0x02) {
      // Metadata
      if (_sessionKey == null) return;
      final decrypted = await decryptChunk(
        EncryptedChunk(
          nonce: payload.sublist(0, 12),
          ciphertext: payload.sublist(12),
        ),
        _sessionKey!,
      );

      final metaStr = utf8.decode(decrypted);
      final List<dynamic> manifestList = jsonDecode(metaStr);
      _manifest = manifestList
          .map((m) => TransferFile(m['name'], m['size']))
          .toList();
      _currentFileIndex = 0;
      _incomingFileSize = _manifest.fold(0, (sum, f) => sum + f.size);

      // Attempt Session-Only Chunk Resume
      if (!kIsWeb && _manifest.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final f = File('${tempDir.path}/${_manifest.first.name}');
        if (f.existsSync()) {
          final offset = f.lengthSync();
          if (offset > 0 && offset < _manifest.first.size) {
            _bytesReceived = offset;
            _manifest.first.bytesReceived = offset;
            final offsetBytes = utf8.encode(offset.toString());
            _rtcEngine!.sendChunk(
              Uint8List.fromList([0x06, ...offsetBytes]),
            ); // Send RESUME_REQ

            if (mounted) {
              setState(() {
                _statusMessage = 'Resuming Transfer from byte $offset...';
              });
              _prepareNextFile();
            }
            return; // Skip the prompt if resuming!
          }
        }
      }

      if (mounted) {
        _showAcceptRejectDialog();
      }
    } else if (type == 0x03) {
      // File Chunk
      if (_sessionKey == null || _manifest.isEmpty) return;

      final decrypted = await decryptChunk(
        EncryptedChunk(
          nonce: payload.sublist(0, 12),
          ciphertext: payload.sublist(12),
        ),
        _sessionKey!,
      );

      final currentFile = _manifest[_currentFileIndex];

      // Inspect Magic Bytes for the very first chunk
      if (currentFile.bytesReceived == 0) {
        try {
          SecurityInspector.inspectMagicBytes(Uint8List.fromList(decrypted));
        } catch (e) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Security Alert: Transfer blocked. $e';
              _isCompleted = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Security Blocked: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          await _rtcEngine?.close();
          return;
        }
      }

      if (!kIsWeb && _tempFile != null) {
        await FileChunker.writeChunk(
          _tempFile!,
          Uint8List.fromList(decrypted),
          append: true,
        );
      } else {
        _webBuffer.addAll(decrypted);
      }

      currentFile.bytesReceived += decrypted.length;
      _bytesReceived += decrypted.length;

      if (mounted) {
        setState(() {
          _progress = _incomingFileSize > 0
              ? _bytesReceived / _incomingFileSize
              : 0.0;
          _statusMessage = 'Receiving ${currentFile.name}...';
        });
      }
    } else if (type == 0x0A) {
      _downloadCurrentFile();
      _currentFileIndex++;
      if (_currentFileIndex < _manifest.length) {
        await _prepareNextFile();
      }
    } else if (type == 0x09) {
      _downloadCurrentFile();
      if (mounted) {
        setState(() {
          _progress = 1.0;
          _statusMessage = 'All files received successfully!';
          _isCompleted = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All files downloaded!')));
      }
      _rtcEngine?.close();
      WakelockPlus.disable();
    }
  }

  void _showAcceptRejectDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Incoming Files'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_manifest.length} file(s) are waiting to be received:'),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _manifest.length,
                  itemBuilder: (ctx, idx) {
                    final file = _manifest[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(file.name),
                      subtitle: Text(
                        '${(file.size / 1024).toStringAsFixed(1)} KB',
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _rejectTransfer();
              },
              child: const Text('Reject', style: TextStyle(color: Colors.red)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _acceptTransfer();
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _acceptTransfer() async {
    if (_rtcEngine == null) return;
    await _rtcEngine!.sendChunk(Uint8List.fromList([0x04])); // 0x04 = Accept
    await _prepareNextFile();
    if (mounted) {
      setState(() {
        _statusMessage = 'Receiving ${_manifest.length} files...';
      });
    }
    WakelockPlus.enable();
  }

  Future<void> _rejectTransfer() async {
    if (_rtcEngine == null) return;
    await _rtcEngine!.sendChunk(Uint8List.fromList([0x05])); // 0x05 = Reject
    await _rtcEngine!.close();
    if (mounted) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Transfer Rejected.';
      });
    }
    WakelockPlus.disable();
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _sessionKey != null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isConnected)
                Card(
                  elevation: 4,
                  shadowColor: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        if (_isScanning)
                          Container(
                            height: 300,
                            width: 300,
                            clipBehavior: Clip.hardEdge,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 4,
                              ),
                            ),
                            child: MobileScanner(
                              onDetect: (capture) {
                                final List<Barcode> barcodes = capture.barcodes;
                                for (final barcode in barcodes) {
                                  if (barcode.rawValue != null) {
                                    setState(() {
                                      _codeController.text = barcode.rawValue!;
                                      _isScanning = false;
                                    });
                                    _connectToPeer();
                                    break;
                                  }
                                }
                              },
                            ),
                          )
                        else ...[
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutBack,
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: child,
                              );
                            },
                            child: Icon(
                              Icons.download,
                              size: 80,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Enter the 6-digit code or scan the QR code.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                        const SizedBox(height: 32),
                        TextField(
                          controller: _codeController,
                          decoration: InputDecoration(
                            hintText: 'e.g. 842-193',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              letterSpacing: 1,
                              fontWeight: FontWeight.normal,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: () {
                                setState(() {
                                  _isScanning = !_isScanning;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            letterSpacing: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLength: 7,
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            setState(() {}); // Rebuild to update button state
                          },
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed:
                                (_codeController.text.length >= 6 &&
                                    !_isConnecting &&
                                    _sessionKey == null)
                                ? _connectToPeer
                                : null,
                            icon: _isConnecting
                                ? Container(
                                    width: 24,
                                    height: 24,
                                    padding: const EdgeInsets.all(2),
                                    child: const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : const Icon(Icons.bolt),
                            label: Text(
                              _isConnecting
                                  ? 'Connecting...'
                                  : 'Connect to Peer',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (isConnected || _progress > 0) ...[
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
                      children: [
                        if (_progress < 1.0) ...[
                          LinearProgressIndicator(
                            value: _progress,
                            borderRadius: BorderRadius.circular(8),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${(_progress * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _statusMessage,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ] else if (_isCompleted) ...[
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
                          const SizedBox(height: 8),
                          Text(
                            _statusMessage,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _resetState,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Receive Another File'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ] else if (_isConnecting) ...[
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
                          _statusMessage,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
