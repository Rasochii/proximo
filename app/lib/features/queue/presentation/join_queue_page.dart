import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/features/queue/domain/eta.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/presentation/queue_providers.dart';
import 'package:proximo/features/shop/domain/shop.dart';
import 'package:proximo/features/shop/presentation/shop_providers.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Fila de uma barbearia aberta pelo link/QR Code (`/b/:slug`), atualizada em tempo real.
///
/// F2: visualização ao vivo da fila pública. O formulário de entrada chega na F4.
class JoinQueuePage extends ConsumerWidget {
  const JoinQueuePage({required this.slug, super.key});

  /// O id do documento da barbearia é o próprio slug.
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shop = ref.watch(shopProvider(slug));
    final queue = ref.watch(publicQueueProvider(slug));

    return Scaffold(
      appBar: AppBar(title: Text(shop.value?.name ?? slug)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
            child: switch ((shop, queue)) {
              (AsyncError(), _) || (_, AsyncError()) => _ErrorView(
                message: l10n.genericError,
                onRetry: () {
                  ref
                    ..invalidate(shopProvider(slug))
                    ..invalidate(publicQueueProvider(slug));
                },
              ),
              (AsyncData(value: null), _) => _MessageView(icon: Icons.storefront_outlined, message: l10n.shopNotFound),
              (AsyncData(value: final Shop _), AsyncData(value: null)) => _MessageView(
                icon: Icons.schedule_rounded,
                message: l10n.queueNotOpenedYet,
              ),
              (AsyncData(value: final Shop _), AsyncData(value: final PublicQueue live)) => _LiveQueueView(queue: live),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }
}

class _LiveQueueView extends StatelessWidget {
  const _LiveQueueView({required this.queue});

  final PublicQueue queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    '${queue.waitingCount}',
                    key: ValueKey(queue.waitingCount),
                    style: theme.textTheme.displayLarge?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                Text(l10n.queueWaitingCount(queue.waitingCount), style: theme.textTheme.titleMedium),
                const Divider(height: Insets.xl),
                Text(l10n.queueEntryEtaLabel, style: theme.textTheme.labelLarge),
                const SizedBox(height: Insets.xs),
                Text(
                  queue.entry.open ? etaText(l10n, queue.entry.eta) : l10n.errorEntriesClosed,
                  style: theme.textTheme.headlineMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.lg),
        Text(l10n.queueNowServing, style: theme.textTheme.titleMedium),
        const SizedBox(height: Insets.sm),
        if (queue.nowServing.isEmpty)
          Text(l10n.queueNobodyServing)
        else
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final ticket in queue.nowServing)
                Chip(
                  avatar: const Icon(Icons.content_cut_rounded, size: 18),
                  label: Text('${l10n.queueTicketNumber(ticket.number)} · ${ticket.label}'),
                ),
            ],
          ),
        if (queue.waiting.isNotEmpty) ...[
          const SizedBox(height: Insets.lg),
          Text(l10n.queueWaitingListTitle, style: theme.textTheme.titleMedium),
          for (final ticket in queue.waiting)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(l10n.queuePosition(ticket.position))),
              title: Text(ticket.label),
              subtitle: Text(l10n.queueTicketNumber(ticket.number)),
              trailing: Text(etaText(l10n, ticket.eta)),
            ),
        ],
      ],
    );
  }
}

/// Texto da previsão: sempre uma faixa, nunca um número "exato".
String etaText(AppLocalizations l10n, Eta eta) => switch (eta) {
  EstimatedEta(startsIn: Duration(inMinutes: <= 0)) => l10n.etaNow,
  EstimatedEta(:final rangeInMinutes) => l10n.etaRange(rangeInMinutes.min, rangeInMinutes.max),
  BeyondClosingEta() => l10n.etaBeyondClosing,
  UnknownEta() => l10n.etaUnknown,
};

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: Insets.md),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: Insets.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Insets.md),
            FilledButton.tonal(onPressed: onRetry, child: Text(AppLocalizations.of(context).retry)),
          ],
        ),
      ),
    );
  }
}
