import 'package:flutter/material.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Entrada do cliente pelo link/QR Code (`/b/:slug`). Implementação completa na fase F4.
class JoinQueuePage extends StatelessWidget {
  const JoinQueuePage({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinQueueTitle(slug))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Text(l10n.comingSoon('F4'), textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
