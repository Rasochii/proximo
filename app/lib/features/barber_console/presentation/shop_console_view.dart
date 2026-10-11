import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/l10n/failure_messages.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/features/barber_console/presentation/shift_controller.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';
import 'package:proximo/features/queue/presentation/queue_providers.dart';
import 'package:proximo/features/queue/presentation/widgets/queue_sections.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Console de uma barbearia para o barbeiro [barberId]: o expediente dele e a fila ao vivo.
///
/// Lê a fila pública (rótulos, sem nome completo). O status do barbeiro também vem dela, então o
/// que a tela mostra é o que o servidor registrou, não o último botão tocado.
///
/// F3/T3: expediente e fila. O "Próximo!" chega na T4.
class ShopConsoleView extends ConsumerWidget {
  const ShopConsoleView({required this.shopId, required this.barberId, super.key});

  final String shopId;

  /// O barbeiro é sempre o usuário logado: o servidor usa o uid dele em todos os comandos.
  final String barberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(publicQueueProvider(shopId));
    final key = (shopId: shopId, barberId: barberId);

    // Quem está de mãos ocupadas sente a mudança antes de olhar: vibração curta quando a situação
    // muda de fato, forte quando o pedido é recusado.
    ref
      ..listen(publicQueueProvider(shopId), (previous, next) {
        final before = previous?.value?.statusOf(barberId) ?? BarberStatus.off;
        final after = next.value?.statusOf(barberId) ?? BarberStatus.off;
        if ((previous?.hasValue ?? false) && before != after) HapticFeedback.mediumImpact();
      })
      ..listen(shiftControllerProvider(key), (previous, next) {
        if (next.failure != null && previous?.failure != next.failure) HapticFeedback.heavyImpact();
      });

    return switch (queue) {
      AsyncError() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: Insets.md),
                Text(
                  l10n.genericError,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Insets.md),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(publicQueueProvider(shopId)),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
      AsyncData(:final value) => _ConsoleBody(shiftKey: key, queue: value),
      _ => Center(child: CircularProgressIndicator(semanticsLabel: l10n.loadingLabel)),
    };
  }
}

class _ConsoleBody extends StatelessWidget {
  const _ConsoleBody({required this.shiftKey, required this.queue});

  final ShiftKey shiftKey;

  /// `null` enquanto ninguém abriu a fila de hoje: o barbeiro ainda não iniciou o expediente.
  final PublicQueue? queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = this.queue;
    final barberId = shiftKey.barberId;

    // O cliente do próprio barbeiro aparece em destaque no cartão; aqui ficam só os dos colegas.
    final servedByOthers = [
      for (final ticket in queue?.nowServing ?? const <ServingTicket>[])
        if (ticket.barberId != barberId) ticket,
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(Insets.lg),
          children: [
            _ShiftCard(
              shiftKey: shiftKey,
              status: queue?.statusOf(barberId) ?? BarberStatus.off,
              serving: queue?.servedBy(barberId),
            ),
            if (servedByOthers.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              NowServingSection(tickets: servedByOthers),
            ],
            if (queue != null) ...[
              const SizedBox(height: Insets.lg),
              // O título já diz quantos esperam ("Ninguém esperando", "3 pessoas esperando").
              // As linhas ficam soltas no ListView para serem construídas sob demanda.
              QueueSectionTitle(l10n.queueWaitingCount(queue.waitingCount)),
              for (final ticket in queue.waiting) WaitingTicketTile(ticket: ticket),
            ],
          ],
        ),
      ),
    );
  }
}

/// Identifica o botão principal do cartão de expediente, qualquer que seja o estilo dele.
const _mainActionKey = ValueKey('shift-main-action');

/// Situação do expediente e as ações que fazem sentido nela.
///
/// Cada situação tem cor, ícone e texto próprios, para ser reconhecida de relance do balcão.
class _ShiftCard extends ConsumerWidget {
  const _ShiftCard({required this.shiftKey, required this.status, required this.serving});

  final ShiftKey shiftKey;
  final BarberStatus status;

  /// Quem este barbeiro está atendendo agora, se houver.
  final ServingTicket? serving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shift = ref.watch(shiftControllerProvider(shiftKey));
    final serving = this.serving;
    final failure = shift.failure;

    VoidCallback? request(BarberStatus next) => shift.busy
        ? null
        : () => ref.read(shiftControllerProvider(shiftKey).notifier).setStatus(next);

    final (title, hint, icon, background, foreground) = switch (status) {
      BarberStatus.off => (
        l10n.consoleShiftOffTitle,
        l10n.consoleShiftOffHint,
        Icons.power_settings_new_rounded,
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
      BarberStatus.available => (
        l10n.consoleShiftAvailable,
        null,
        Icons.content_cut_rounded,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      BarberStatus.paused => (
        l10n.consoleShiftPaused,
        l10n.consoleShiftPausedHint,
        Icons.pause_circle_outline_rounded,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
    };

    // Com um pedido em aberto, o botão principal diz o que está acontecendo.
    final pendingLabel = switch (shift.requested) {
      null => null,
      BarberStatus.off => l10n.consoleShiftEnding,
      BarberStatus.paused => l10n.consoleShiftPausing,
      BarberStatus.available =>
        status == BarberStatus.paused ? l10n.consoleShiftResuming : l10n.consoleShiftStarting,
    };
    final (actionLabel, actionTarget) = switch (status) {
      BarberStatus.off => (l10n.consoleShiftStartAction, BarberStatus.available),
      BarberStatus.available => (l10n.consoleShiftPauseAction, BarberStatus.paused),
      BarberStatus.paused => (l10n.consoleShiftResumeAction, BarberStatus.available),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      color: background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Reserva a altura da barra para o cartão não pular quando um pedido começa ou termina.
          SizedBox(
            height: Insets.xs,
            child: pendingLabel == null
                ? null
                : LinearProgressIndicator(semanticsLabel: pendingLabel),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.sm, Insets.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: Insets.xl, color: foreground),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      // A mudança de situação é anunciada por leitores de tela.
                      child: Semantics(
                        header: true,
                        headingLevel: 2,
                        liveRegion: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(color: foreground),
                        ),
                      ),
                    ),
                    // Encerrar tira o barbeiro da fila pública: fica a dois toques, como o "Sair",
                    // para um esbarrão no balcão não encerrar o expediente.
                    if (status != BarberStatus.off)
                      PopupMenuButton<void>(
                        tooltip: l10n.consoleShiftMoreActions,
                        enabled: !shift.busy,
                        iconColor: foreground,
                        itemBuilder: (context) => [
                          PopupMenuItem<void>(
                            onTap: request(BarberStatus.off),
                            child: Text(l10n.consoleShiftEndAction),
                          ),
                        ],
                      )
                    else
                      const SizedBox(width: Insets.md),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: Insets.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hint != null) ...[
                        const SizedBox(height: Insets.sm),
                        Text(hint, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
                      ],
                      if (serving != null) ...[
                        const SizedBox(height: Insets.md),
                        Text(
                          l10n.consoleServingNowLabel,
                          style: theme.textTheme.labelLarge?.copyWith(color: foreground),
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            '${l10n.queueTicketNumber(serving.number)} · ${serving.label}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: foreground,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                      // O motivo de um pedido recusado fica no cartão até a próxima tentativa:
                      // um aviso passageiro passaria despercebido por quem olha de relance.
                      if (failure != null) ...[
                        const SizedBox(height: Insets.md),
                        Semantics(
                          liveRegion: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(Insets.radius),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(Insets.md),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
                                  const SizedBox(width: Insets.sm),
                                  Expanded(
                                    child: Text(
                                      l10n.failureMessage(failure),
                                      style: theme.textTheme.bodyLarge?.copyWith(
                                        color: scheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: Insets.lg),
                      // As cores vêm do cartão, para o botão contrastar com o fundo de cada situação.
                      // Em expediente a pausa é ação secundária (contorno); nas outras duas, a
                      // ação é o caminho de volta ao trabalho e ganha o botão cheio.
                      switch (status) {
                        BarberStatus.available => OutlinedButton(
                          key: _mainActionKey,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: foreground,
                            side: BorderSide(color: foreground),
                            minimumSize: const Size.fromHeight(Insets.controlHeight),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Insets.radius),
                            ),
                          ),
                          onPressed: request(actionTarget),
                          child: Text(pendingLabel ?? actionLabel),
                        ),
                        BarberStatus.paused => FilledButton(
                          key: _mainActionKey,
                          style: FilledButton.styleFrom(
                            backgroundColor: foreground,
                            foregroundColor: background,
                          ),
                          onPressed: request(actionTarget),
                          child: Text(pendingLabel ?? actionLabel),
                        ),
                        BarberStatus.off => FilledButton(
                          key: _mainActionKey,
                          onPressed: request(actionTarget),
                          child: Text(pendingLabel ?? actionLabel),
                        ),
                      },
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
