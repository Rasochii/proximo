import 'package:flutter/material.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/features/queue/domain/eta.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Blocos da fila pública, usados na coluna única do celular e nas colunas do layout de site.

/// Texto da previsão: sempre uma faixa, nunca um número "exato".
String etaText(AppLocalizations l10n, Eta eta) => switch (eta) {
  EstimatedEta(startsIn: Duration(inMinutes: <= 0)) => l10n.etaNow,
  EstimatedEta(:final rangeInMinutes) => l10n.etaRange(rangeInMinutes.min, rangeInMinutes.max),
  BeyondClosingEta() => l10n.etaBeyondClosing,
  UnknownEta() => l10n.etaUnknown,
};

/// Título de uma seção da fila, anunciado como título para leitores de tela.
class QueueSectionTitle extends StatelessWidget {
  const QueueSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      headingLevel: 2,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Quantas pessoas esperam e quanto esperaria quem entrasse agora.
class QueueSummaryCard extends StatelessWidget {
  const QueueSummaryCard({required this.queue, super.key});

  final PublicQueue queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // O número é repetido por extenso logo abaixo; o leitor de tela lê só a frase.
            ExcludeSemantics(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  '${queue.waitingCount}',
                  key: ValueKey(queue.waitingCount),
                  style: theme.textTheme.displayLarge?.copyWith(color: theme.colorScheme.primary),
                ),
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
    );
  }
}

/// Quem está na cadeira agora. Recebe a lista pronta para o console poder mostrar só os outros
/// barbeiros.
class NowServingSection extends StatelessWidget {
  const NowServingSection({required this.tickets, super.key});

  final List<ServingTicket> tickets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QueueSectionTitle(l10n.queueNowServing),
        const SizedBox(height: Insets.sm),
        if (tickets.isEmpty)
          Text(l10n.queueNobodyServing)
        else
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final ticket in tickets)
                Chip(
                  avatar: const Icon(Icons.content_cut_rounded, size: 18),
                  label: Text('${l10n.queueTicketNumber(ticket.number)} · ${ticket.label}'),
                ),
            ],
          ),
      ],
    );
  }
}

/// A fila de espera, na ordem de atendimento. Vazia, diz isso em vez de mostrar só o título.
class WaitingListSection extends StatelessWidget {
  const WaitingListSection({required this.queue, super.key});

  final PublicQueue queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QueueSectionTitle(l10n.queueWaitingListTitle),
        if (queue.waiting.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Text(l10n.queueWaitingEmpty),
          ),
        for (final ticket in queue.waiting) WaitingTicketTile(ticket: ticket),
      ],
    );
  }
}

/// Uma pessoa na fila: posição, rótulo público, número e previsão.
class WaitingTicketTile extends StatelessWidget {
  const WaitingTicketTile({required this.ticket, super.key});

  final WaitingTicket ticket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Linha própria em vez de `ListTile`: o `trailing` dele não quebra linha e estoura com letra
    // grande, e usa 11 sp justamente na previsão, que é o que a pessoa procura.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: [
          CircleAvatar(child: Text(l10n.queuePosition(ticket.position))),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticket.label, style: theme.textTheme.bodyLarge),
                Text(
                  l10n.queueTicketNumber(ticket.number),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          // As duas colunas dividem a linha: a previsão encosta na direita e quebra se precisar.
          Expanded(
            child: Text(
              etaText(l10n, ticket.eta),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
