import 'package:flutter/material.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Console do barbeiro ("Próximo!", Desfazer, Não veio…). Implementação completa na fase F3.
class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeBarberTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Text(l10n.comingSoon('F3'), textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
