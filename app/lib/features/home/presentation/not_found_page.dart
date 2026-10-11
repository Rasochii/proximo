import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/core/widgets/site_shell.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 64),
              const SizedBox(height: Insets.md),
              Text(l10n.notFoundTitle, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: Insets.lg),
              SelectionContainer.disabled(
                child: FilledButton.tonal(
                  onPressed: () => context.goNamed(AppRoutes.home),
                  child: Text(l10n.backToHome),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // No layout de site a página perdida também tem o cabeçalho, para a pessoa se localizar.
    return Breakpoints.isWide(context) ? SitePage(child: content) : Scaffold(body: content);
  }
}
