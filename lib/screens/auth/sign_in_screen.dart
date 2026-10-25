import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../utils/phone.dart';
import '../../widgets/states.dart';
import '../auth_gate.dart';
import 'otp_screen.dart';

enum _Method { phone, email }

/// Registration and login. Phone + SMS code is the main method; email and
/// password is available for testing (free on the Spark plan).
class SignInScreen extends StatefulWidget {
  final bool register;
  const SignInScreen({super.key, required this.register});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

void goToAuthGate(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (_) => false,
  );
}

class _SignInScreenState extends State<SignInScreen> {
  late _Method _method =
      AppConfig.phoneAuthEnabled ? _Method.phone : _Method.email;

  @override
  Widget build(BuildContext context) {
    final both = AppConfig.phoneAuthEnabled && AppConfig.emailAuthEnabled;
    return Scaffold(
      appBar: AppBar(
          title:
              Text(context.tr(widget.register ? 'create_account' : 'log_in'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (both) ...[
              SegmentedButton<_Method>(
                segments: [
                  ButtonSegment(
                      value: _Method.phone,
                      icon: const Icon(Icons.phone),
                      label: Text(context.tr('phone'))),
                  ButtonSegment(
                      value: _Method.email,
                      icon: const Icon(Icons.email_outlined),
                      label: Text(context.tr('email'))),
                ],
                selected: {_method},
                onSelectionChanged: (s) => setState(() => _method = s.first),
              ),
              const SizedBox(height: 24),
            ],
            if (_method == _Method.phone)
              _PhoneForm(register: widget.register)
            else
              _EmailForm(register: widget.register),
          ],
        ),
      ),
    );
  }
}

class _PhoneForm extends StatefulWidget {
  final bool register;
  const _PhoneForm({required this.register});

  @override
  State<_PhoneForm> createState() => _PhoneFormState();
}

class _PhoneFormState extends State<_PhoneForm> {
  final _phone = TextEditingController();
  late Country _country;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final region =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    _country = _tryCountry(region) ?? _tryCountry('SO')!;
  }

  Country? _tryCountry(String? code) {
    if (code == null || code.isEmpty) return null;
    try {
      return Country.parse(code);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final e164 = toE164(_country.phoneCode, _phone.text);
    if (!isPlausibleE164(e164)) {
      setState(() => _error = context.tr('err_invalid_phone'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await AuthService.instance.sendCode(
      phoneNumber: e164,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() => _busy = false);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpScreen(
              phoneNumber: e164,
              verificationId: verificationId,
              resendToken: resendToken),
        ));
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('phone_intro'), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => showCountryPicker(
                    context: context,
                    showPhoneCode: true,
                    onSelect: (c) => setState(() => _country = c),
                  ),
          child: Row(
            children: [
              Text(_country.flagEmoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(_country.name, overflow: TextOverflow.ellipsis)),
              Text('+${_country.phoneCode}', textDirection: TextDirection.ltr),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Directionality(
          // Phone numbers are always written left to right.
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()+-]'))
            ],
            decoration: InputDecoration(
              labelText: context.tr('phone_number'),
              prefixText: '+${_country.phoneCode} ',
              errorText: _error,
              errorMaxLines: 5,
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(height: 8),
        Text(context.tr('sms_billing_note'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: _busy ? const ButtonSpinner() : Text(context.tr('send_code')),
        ),
      ],
    );
  }
}

class _EmailForm extends StatefulWidget {
  final bool register;
  const _EmailForm({required this.register});

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = context.tr('err_invalid_email'));
      return;
    }
    if (password.length < 8) {
      setState(() => _error = context.tr('err_weak_password'));
      return;
    }
    if (widget.register && password != _confirm.text) {
      setState(() => _error = context.tr('err_passwords_differ'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.register) {
        await AuthService.instance.registerWithEmail(email, password);
      } else {
        await AuthService.instance.signInWithEmail(email, password);
      }
      if (mounted) goToAuthGate(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr(AuthService.errorKey(e.code));
      });
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = context.tr('enter_email_first'));
      return;
    }
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) showSnack(context, context.tr('reset_email_sent'));
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(() => _error = context.tr(AuthService.errorKey(e.code)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('email_intro'), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: context.tr('email')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: _obscure,
            autofillHints: [
              widget.register
                  ? AutofillHints.newPassword
                  : AutofillHints.password
            ],
            decoration: InputDecoration(
              labelText: context.tr('password'),
              helperText: widget.register ? context.tr('password_hint') : null,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: widget.register ? null : (_) => _submit(),
          ),
          if (widget.register) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: _obscure,
              decoration:
                  InputDecoration(labelText: context.tr('confirm_password')),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const ButtonSpinner()
                : Text(
                    context.tr(widget.register ? 'create_account' : 'log_in')),
          ),
          if (!widget.register) ...[
            const SizedBox(height: 8),
            TextButton(
                onPressed: _busy ? null : _forgot,
                child: Text(context.tr('forgot_password'))),
          ],
        ],
      ),
    );
  }
}
