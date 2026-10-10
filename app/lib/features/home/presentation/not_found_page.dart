import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 64),
              const SizedBox(height: Insets.md),
              Text(l10n.notFoundTitle, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: Insets.lg),
              FilledButton.tonal(
                onPressed: () => context.goNamed(AppRoutes.home),
                child: Text(l10n.backToHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
