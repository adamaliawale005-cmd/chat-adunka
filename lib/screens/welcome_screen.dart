import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'auth/sign_in_screen.dart';
import 'settings/language_sheet.dart';
import 'setup_required_screen.dart';

/// First screen: the original Chat Aduunka welcome, with sign-up and log-in.
class WelcomeScreen extends StatelessWidget {
  final bool firebaseReady;
  final Object? firebaseError;

  const WelcomeScreen({super.key, required this.firebaseReady, this.firebaseError});

  void _go(BuildContext context, {required bool register}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => firebaseReady
          ? SignInScreen(register: register)
          : SetupRequiredScreen(error: firebaseError),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AduChat'),
        actions: [
          IconButton(
            tooltip: context.tr('language'),
            icon: const Icon(Icons.language),
            onPressed: () => showLanguageSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/branding/logo.png', width: 110, height: 110),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('welcome_title'),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('welcome_subtitle'),
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      FilledButton.icon(
                        onPressed: () => _go(context, register: true),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(context.tr('create_account')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _go(context, register: false),
                        icon: const Icon(Icons.login),
                        label: Text(context.tr('log_in')),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        context.tr('terms_notice'),
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
