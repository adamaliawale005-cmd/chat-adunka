import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import 'otp_screen.dart';

/// Converts a country dial code and a locally typed number to E.164,
/// e.g. ("252", "061 234 5678") -> "+252612345678".
String toE164(String dialCode, String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  // People often type the national trunk prefix (0) or the country code again.
  if (digits.startsWith('00$dialCode')) digits = digits.substring(2 + dialCode.length);
  if (digits.startsWith(dialCode) && digits.length > dialCode.length + 6) {
    digits = digits.substring(dialCode.length);
  }
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  return '+$dialCode$digits';
}

bool isPlausibleE164(String e164) => RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(e164);

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phone = TextEditingController();
  late Country _country;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
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

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (c) => setState(() => _country = c),
    );
  }

  Future<void> _send() async {
    final e164 = toE164(_country.phoneCode, _phone.text);
    if (!isPlausibleE164(e164)) {
      setState(() => _error = 'Enter a valid phone number.');
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
            resendToken: resendToken,
          ),
        ));
      },
      onAutoVerified: () {
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your phone number')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Chat Aduunka will send an SMS with a verification code to confirm your number.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : _pickCountry,
              child: Row(
                children: [
                  Text(_country.flagEmoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_country.name, overflow: TextOverflow.ellipsis)),
                  Text('+${_country.phoneCode}'),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ()+-]'))],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Phone number',
                prefixText: '+${_country.phoneCode} ',
                errorText: _error,
                errorMaxLines: 4,
              ),
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send code'),
            ),
          ],
        ),
      ),
    );
  }
}
