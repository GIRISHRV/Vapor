import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/panic_engine.dart';
import 'components/vapor_components.dart';

class LockScreenOverlay extends StatefulWidget {
  final VoidCallback? onUnlock;
  const LockScreenOverlay({super.key, this.onUnlock});

  @override
  State<LockScreenOverlay> createState() => _LockScreenOverlayState();
}

class _LockScreenOverlayState extends State<LockScreenOverlay> {
  String _input = '';
  String _realPin = '';
  String _duressPin = '';
  bool _isSetupMode = false;
  int _setupStep =
      0; // 0: enter real, 1: confirm real, 2: enter duress, 3: confirm duress
  String _tempSetupPin = '';
  bool _isLoading = true;

  String _salt = '';

  @override
  void initState() {
    super.initState();
    _checkExistingPins();
  }

  Future<String> _hashPin(String pin, String salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = SecretKey(utf8.encode(pin));
    final result = await pbkdf2.deriveKey(
      secretKey: secretKey,
      nonce: utf8.encode(salt),
    );
    final bytes = await result.extractBytes();
    return base64Encode(bytes);
  }

  Future<void> _checkExistingPins() async {
    final prefs = await SharedPreferences.getInstance();
    String? real = prefs.getString('vapor_real_pin');
    String? duress = prefs.getString('vapor_duress_pin');
    String? salt = prefs.getString('vapor_pin_salt');

    // Force setup if salt is missing (migrating away from weak SHA-256)
    if (real == null || duress == null || salt == null) {
      setState(() {
        _isSetupMode = true;
        _isLoading = false;
      });
    } else {
      setState(() {
        _realPin = real;
        _duressPin = duress;
        _salt = salt;
        _isLoading = false;
      });
    }
  }

  void _onKeyPress(String key) {
    if (_input.length < 4) {
      setState(() {
        _input += key;
      });

      if (_input.length == 4) {
        Future.delayed(const Duration(milliseconds: 200), _processInput);
      }
    }
  }

  void _onDelete() {
    if (_input.isNotEmpty) {
      setState(() {
        _input = _input.substring(0, _input.length - 1);
      });
    }
  }

  Future<void> _processInput() async {
    if (_isSetupMode) {
      if (_setupStep == 0) {
        _tempSetupPin = _input;
        setState(() {
          _input = '';
          _setupStep = 1;
        });
      } else if (_setupStep == 1) {
        if (_input == _tempSetupPin) {
          _realPin = _input;
          setState(() {
            _input = '';
            _setupStep = 2;
          });
        } else {
          _showError('PIN mismatch. Try again.');
          setState(() {
            _input = '';
            _setupStep = 0;
          });
        }
      } else if (_setupStep == 2) {
        if (_input == _realPin) {
          _showError('Duress PIN cannot be same as Real PIN.');
          setState(() {
            _input = '';
          });
        } else {
          _tempSetupPin = _input;
          setState(() {
            _input = '';
            _setupStep = 3;
          });
        }
      } else if (_setupStep == 3) {
        if (_input == _tempSetupPin) {
          _duressPin = _input;
          final prefs = await SharedPreferences.getInstance();
          
          // Generate a secure random per-install salt
          final saltBytes = List<int>.generate(16, (i) => Random.secure().nextInt(256));
          final salt = base64Encode(saltBytes);

          final hashedReal = await _hashPin(_realPin, salt);
          final hashedDuress = await _hashPin(_duressPin, salt);

          await prefs.setString('vapor_pin_salt', salt);
          await prefs.setString('vapor_real_pin', hashedReal);
          await prefs.setString('vapor_duress_pin', hashedDuress);
          
          setState(() {
            _salt = salt;
            _realPin = hashedReal;
            _duressPin = hashedDuress;
            _isSetupMode = false;
            _input = '';
          });
          // If this was a setup overlay from boot, we can dismiss it
          if (widget.onUnlock != null) {
            widget.onUnlock!();
          } else if (mounted) {
            Navigator.of(context).pop();
          }
        } else {
          _showError('PIN mismatch. Try again.');
          setState(() {
            _input = '';
            _setupStep = 2;
          });
        }
      }
    } else {
      // Verification Mode — compare hashes using PBKDF2
      final inputHash = await _hashPin(_input, _salt);
      if (inputHash == _realPin) {
        // Success
        if (widget.onUnlock != null) {
          widget.onUnlock!();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      } else if (inputHash == _duressPin) {
        // DURESS TRIGGERED!
        if (mounted) {
          // Silently trigger wipe and redirect to dashboard via PanicEngine
          PanicEngine.triggerPanicWipe(context);
        }
      } else {
        _showError('Incorrect PIN');
        setState(() {
          _input = '';
        });
      }
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  String get _titleText {
    if (!_isSetupMode) return 'Enter Passcode';
    switch (_setupStep) {
      case 0:
        return 'Create Real PIN';
      case 1:
        return 'Confirm Real PIN';
      case 2:
        return 'Create Duress (Wipe) PIN';
      case 3:
        return 'Confirm Duress PIN';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const VaporScaffold(
        hideAppBar: true,
        body: Center(child: VaporProgress()),
      );
    }

    return VaporScaffold(
      hideAppBar: true,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 24),
            Text(
              _titleText,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < _input.length
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 48),
            _buildNumpad(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 1; i <= 9; i++) _buildNumKey(i.toString()),
          const SizedBox.shrink(),
          _buildNumKey('0'),
          IconButton(
            onPressed: _onDelete,
            icon: const Icon(Icons.backspace_outlined),
            iconSize: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildNumKey(String num) {
    return Center(
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _onKeyPress(num),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          child: Text(
            num,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
