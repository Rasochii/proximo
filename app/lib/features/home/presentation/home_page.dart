import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Tela inicial: o cliente digita o código da barbearia (ou chega direto pelo QR Code)
/// e o barbeiro entra no console.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.all(Insets.lg),
              shrinkWrap: true,
              children: [
                Text(
                  l10n.appTitle,
                  style: theme.textTheme.displayMedium?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: Insets.sm),
                Text(l10n.homeTagline, style: theme.textTheme.titleMedium),
                const SizedBox(height: Insets.xl),
                const _JoinByCodeCard(),
                const SizedBox(height: Insets.md),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Insets.lg,
                      vertical: Insets.sm,
                    ),
                    leading: const Icon(Icons.content_cut_rounded),
                    title: Text(l10n.homeBarberTitle),
                    subtitle: Text(l10n.homeBarberSubtitle),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.goNamed(AppRoutes.console),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinByCodeCard extends StatefulWidget {
  const _JoinByCodeCard();

  @override
  State<_JoinByCodeCard> createState() => _JoinByCodeCardState();
}

class _JoinByCodeCardState extends State<_JoinByCodeCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final slug = _controller.text.trim().toLowerCase();
    if (slug.isEmpty) return;
    context.goNamed(AppRoutes.joinQueue, pathParameters: {'slug': slug});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.homeJoinTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _controller,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                hintText: l10n.homeJoinHint,
                prefixIcon: const Icon(Icons.storefront_rounded),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Insets.md),
            FilledButton(onPressed: _submit, child: Text(l10n.homeJoinAction)),
          ],
        ),
      ),
    );
  }
}
