import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../widgets/states.dart';
import 'sign_in_screen.dart';

/// Enter the 6-digit SMS code.
class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;

  const OtpScreen({super.key, required this.phoneNumber, required this.verificationId, this.resendToken});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  late String _verificationId = widget.verificationId;
  late int? _resendToken = widget.resendToken;
  bool _busy = false;
  String? _error;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = _secondsLeft <= 1 ? 0 : _secondsLeft - 1);
      if (_secondsLeft == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = context.tr('enter_6_digits'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.verifyCode(verificationId: _verificationId, smsCode: code);
      if (mounted) goToAuthGate(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr(AuthService.errorKey(e.code));
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await AuthService.instance.sendCode(
      phoneNumber: widget.phoneNumber,
      resendToken: _resendToken,
      onCodeSent: (id, token) {
        if (!mounted) return;
        setState(() {
          _verificationId = id;
          _resendToken = token;
          _busy = false;
        });
        _startTimer();
      },
      onAutoVerified: () {
        if (mounted) goToAuthGate(context);
      },
      onError: (code) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = context.tr(AuthService.errorKey(code));
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('verify_number'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              context.tr('code_sent_to', {'phone': '⁦${widget.phoneNumber}⁩'}),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 12),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(counterText: '', errorText: _error, errorMaxLines: 5),
                onChanged: (v) {
                  if (v.length == 6) _verify();
                },
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _verify,
              child: _busy ? const ButtonSpinner() : Text(context.tr('verify')),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: (_busy || _secondsLeft > 0) ? null : _resend,
              child: Text(_secondsLeft > 0
                  ? context.tr('resend_in', {'seconds': _secondsLeft})
                  : context.tr('resend_code')),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(context.tr('change_number')),
            ),
          ],
        ),
      ),
    );
  }
}
