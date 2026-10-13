import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/l10n/failure_messages.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/features/barber_console/presentation/console_controller.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';
import 'package:proximo/features/queue/presentation/queue_providers.dart';
import 'package:proximo/features/queue/presentation/widgets/queue_sections.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// A barra de ação existe quando há o que fazer nela: em expediente, ou em pausa com alguém na
/// cadeira para terminar.
bool _showsActionBar(BarberStatus status, ServingTicket? serving) =>
    status == BarberStatus.available || (status == BarberStatus.paused && serving != null);

/// Console de uma barbearia para o barbeiro [barberId]: o expediente dele e a fila ao vivo.
///
/// Lê a fila pública (rótulos, sem nome completo). O status do barbeiro também vem dela, então o
/// que a tela mostra é o que o servidor registrou, não o último botão tocado.
///
/// O botão "Próximo!" fica em [ShopConsoleActionBar], na parte de baixo da tela.
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

    ref
      // Quem está de mãos ocupadas sente a mudança antes de olhar: vibração curta quando a
      // situação muda de fato, forte quando o pedido é recusado.
      ..listen(publicQueueProvider(shopId), (previous, next) {
        final before = previous?.value?.statusOf(barberId) ?? BarberStatus.off;
        final after = next.value?.statusOf(barberId) ?? BarberStatus.off;
        if ((previous?.hasValue ?? false) && before != after) HapticFeedback.mediumImpact();
      })
      ..listen(consoleControllerProvider(key).select((state) => state.failure), (previous, next) {
        if (next != null && previous != next) HapticFeedback.heavyImpact();
      })
      // Avanço aceito: avisa o que aconteceu e oferece desfazer, em vez de pedir confirmação
      // antes. O aviso acompanha o estado: sai da tela quando o controller deixa de oferecer o
      // Desfazer (desfeito, recusado ou vencido o prazo).
      ..listen(consoleControllerProvider(key).select((state) => state.lastAdvance), (
        previous,
        next,
      ) {
        final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
        if (next == null) return;

        // Um aviso reposto (o mesmo avanço, depois de um Desfazer que não saiu) não vibra de novo.
        if (previous?.result != next.result) HapticFeedback.mediumImpact();
        final called = next.result.called;
        final noShow = next.result.finishedOutcome == FinishOutcome.noShow;
        final message = switch ((called, noShow)) {
          // "Não veio" e "Próximo!" chamam a mesma pessoa: o aviso precisa dizer qual dos dois foi.
          (final CalledTicket called, true) => l10n.consoleNoShowCalledNotice(
            called.number,
            called.label,
          ),
          (final CalledTicket called, false) => l10n.consoleCalledNotice(
            called.number,
            called.label,
          ),
          (null, true) => l10n.consoleNoShowNotice,
          (null, false) => l10n.consoleFinishedNotice,
        };
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: next.undoFor,
            // Com uma ação, o SnackBar por padrão não some sozinho; aqui ele tem prazo.
            persist: false,
            // Em tela larga o aviso fica na mesma coluna dos botões, e não de ponta a ponta.
            width: MediaQuery.sizeOf(context).width > Insets.maxContentWidth
                ? Insets.maxContentWidth - 2 * Insets.lg
                : null,
            action: SnackBarAction(
              label: l10n.undoAction,
              onPressed: () => ref.read(consoleControllerProvider(key).notifier).undoLast(),
            ),
          ),
        );
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
      AsyncData(:final value) => _ConsoleBody(consoleKey: key, queue: value),
      _ => Center(child: CircularProgressIndicator(semanticsLabel: l10n.loadingLabel)),
    };
  }
}

class _ConsoleBody extends StatelessWidget {
  const _ConsoleBody({required this.consoleKey, required this.queue});

  final ConsoleKey consoleKey;

  /// `null` enquanto ninguém abriu a fila de hoje: o barbeiro ainda não iniciou o expediente.
  final PublicQueue? queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = this.queue;
    final barberId = consoleKey.barberId;

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
              consoleKey: consoleKey,
              status: queue?.statusOf(barberId) ?? BarberStatus.off,
              serving: queue?.servedBy(barberId),
              entriesClosed: queue?.entriesClosedByStaff ?? false,
              hasQueue: queue != null,
            ),
            if (servedByOthers.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              NowServingSection(tickets: servedByOthers),
            ],
            if (queue != null) ...[
              const SizedBox(height: Insets.lg),
              // O título já diz quantos esperam ("Ninguém esperando", "3 pessoas esperando").
              // As linhas ficam soltas no ListView para serem construídas sob demanda.
              if (queue.entriesClosedByStaff) ...[
                _EntriesClosedNotice(consoleKey: consoleKey),
                const SizedBox(height: Insets.lg),
              ],
              QueueSectionTitle(l10n.queueWaitingCount(queue.waitingCount)),
              for (final ticket in queue.waiting)
                _RemovableTicket(
                  key: ValueKey(ticket.ticketId),
                  consoleKey: consoleKey,
                  ticket: ticket,
                ),
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
  const _ShiftCard({
    required this.consoleKey,
    required this.status,
    required this.serving,
    required this.entriesClosed,
    required this.hasQueue,
  });

  final ConsoleKey consoleKey;
  final BarberStatus status;

  /// A fila de hoje já existe (alguém iniciou o expediente ou entrou nela).
  final bool hasQueue;

  /// A equipe fechou a entrada de novos clientes.
  final bool entriesClosed;

  /// Quem este barbeiro está atendendo agora, se houver.
  final ServingTicket? serving;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final console = ref.watch(consoleControllerProvider(consoleKey));
    final controller = ref.read(consoleControllerProvider(consoleKey).notifier);
    final serving = this.serving;
    // Com a barra de ação na tela, a falha aparece nela: perto do dedo e à vista mesmo com a
    // lista rolada. Aqui só quando a barra não existe.
    final failure = _showsActionBar(status, serving) ? null : console.failure;

    VoidCallback? whenFree(VoidCallback action) => console.busy ? null : action;

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

    // Com um pedido de expediente em aberto, o botão principal diz o que está acontecendo.
    final pendingLabel = switch (console.pending) {
      ConsoleAction.startShift => l10n.consoleShiftStarting,
      ConsoleAction.resume => l10n.consoleShiftResuming,
      ConsoleAction.pause => l10n.consoleShiftPausing,
      ConsoleAction.endShift => l10n.consoleShiftEnding,
      _ => null,
    };
    // Estas não trocam o texto do botão de expediente; só acendem a barra de progresso.
    final otherPending = switch (console.pending) {
      ConsoleAction.closeEntries => l10n.consoleClosingEntries,
      ConsoleAction.openEntries => l10n.consoleOpeningEntries,
      ConsoleAction.removeTicket => l10n.consoleRemoving,
      _ => null,
    };
    final (actionLabel, action) = switch (status) {
      BarberStatus.off => (l10n.consoleShiftStartAction, controller.startShift),
      BarberStatus.available => (l10n.consoleShiftPauseAction, controller.pause),
      BarberStatus.paused => (
        l10n.consoleShiftResumeAction,
        () => controller.startShift(resuming: true),
      ),
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
            child: (pendingLabel ?? otherPending) == null
                ? null
                : LinearProgressIndicator(semanticsLabel: pendingLabel ?? otherPending),
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
                    // Fechar a entrada vale também fora do expediente (o dono que não corta, ou
                    // quem já encerrou): basta a fila de hoje existir.
                    if (status != BarberStatus.off || hasQueue)
                      PopupMenuButton<void>(
                        tooltip: l10n.consoleShiftMoreActions,
                        enabled: !console.busy,
                        iconColor: foreground,
                        itemBuilder: (context) => [
                          // Fechar a entrada também fica a dois toques: barra os clientes novos.
                          PopupMenuItem<void>(
                            onTap: whenFree(
                              () => controller.setAcceptingEntries(accepting: entriesClosed),
                            ),
                            child: Text(
                              entriesClosed
                                  ? l10n.consoleOpenEntriesAction
                                  : l10n.consoleCloseEntriesAction,
                            ),
                          ),
                          if (status != BarberStatus.off)
                            PopupMenuItem<void>(
                              onTap: whenFree(controller.endShift),
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
                      if (failure != null) ...[
                        const SizedBox(height: Insets.md),
                        _FailureNotice(failure: failure),
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
                          onPressed: whenFree(action),
                          child: Text(pendingLabel ?? actionLabel),
                        ),
                        BarberStatus.paused => FilledButton(
                          key: _mainActionKey,
                          style: FilledButton.styleFrom(
                            backgroundColor: foreground,
                            foregroundColor: background,
                          ),
                          onPressed: whenFree(action),
                          child: Text(pendingLabel ?? actionLabel),
                        ),
                        BarberStatus.off => FilledButton(
                          key: _mainActionKey,
                          onPressed: whenFree(action),
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

/// Aviso de que a entrada está fechada, com o caminho de volta à mão: uma entrada esquecida
/// fechada deixa a barbearia sem clientes novos sem ninguém perceber.
class _EntriesClosedNotice extends ConsumerWidget {
  const _EntriesClosedNotice({required this.consoleKey});

  final ConsoleKey consoleKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final console = ref.watch(consoleControllerProvider(consoleKey));
    final busy = console.busy;

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(Insets.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.door_front_door_outlined, color: scheme.onTertiaryContainer),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.consoleEntriesClosedNotice,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, Insets.touchTarget)),
                  onPressed: busy
                      ? null
                      : () => ref
                            .read(consoleControllerProvider(consoleKey).notifier)
                            .setAcceptingEntries(accepting: true),
                  child: Text(
                    console.pending == ConsoleAction.openEntries
                        ? l10n.consoleOpeningEntries
                        : l10n.consoleOpenEntriesAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma pessoa da espera, com o botão para tirá-la da fila.
///
/// O servidor não desfaz a remoção, então aqui há confirmação: é uma ação rara e sem volta, ao
/// contrário do "Próximo!". É um botão, e não um gesto de arrastar: funciona com mouse, teclado
/// e leitor de tela, e não dispara ao rolar a lista.
class _RemovableTicket extends ConsumerWidget {
  const _RemovableTicket({required this.consoleKey, required this.ticket, super.key});

  final ConsoleKey consoleKey;
  final WaitingTicket ticket;

  Future<void> _confirmAndRemove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return AlertDialog(
          title: Text(l10n.consoleRemoveTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.queueTicketNumber(ticket.number)} · ${ticket.label}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Insets.sm),
              Text(l10n.consoleRemoveBody),
            ],
          ),
          actions: [
            // O foco começa na saída segura; a ação sem volta leva a cor de erro. Os tamanhos
            // são explícitos porque o tema estica os botões cheios na largura toda.
            OutlinedButton(
              autofocus: true,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, Insets.touchTarget)),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.consoleRemoveCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Insets.touchTarget),
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.consoleRemoveConfirm),
            ),
          ],
        );
      },
    );
    // Com o diálogo aberto a fila continua ao vivo: a pessoa pode ter sido chamada ou saído, e
    // esta linha (dona do `ref`) pode não existir mais.
    if (!(confirmed ?? false) || !context.mounted) return;
    unawaited(
      ref.read(consoleControllerProvider(consoleKey).notifier).removeTicket(ticket.ticketId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final console = ref.watch(consoleControllerProvider(consoleKey));
    final removing =
        console.pending == ConsoleAction.removeTicket &&
        ref.read(consoleControllerProvider(consoleKey).notifier).removingTicketId ==
            ticket.ticketId;

    return Row(
      children: [
        Expanded(
          // Lida de uma vez pelo leitor de tela; esmaecida enquanto a remoção está a caminho.
          child: Opacity(
            opacity: removing ? 0.5 : 1,
            child: MergeSemantics(child: WaitingTicketTile(ticket: ticket)),
          ),
        ),
        if (removing)
          SizedBox.square(
            dimension: Insets.touchTarget,
            child: Padding(
              padding: const EdgeInsets.all(Insets.md - Insets.xs),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                semanticsLabel: l10n.consoleRemoving,
              ),
            ),
          )
        else
          IconButton(
            tooltip: l10n.consoleRemoveWho(ticket.number, ticket.label),
            icon: const Icon(Icons.person_remove_outlined),
            color: scheme.onSurfaceVariant,
            onPressed: console.busy ? null : () => _confirmAndRemove(context, ref),
          ),
      ],
    );
  }
}

/// O motivo de um pedido recusado. Fica na tela até a próxima tentativa: um aviso passageiro
/// passaria despercebido por quem olha de relance.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
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
                  AppLocalizations.of(context).failureMessage(failure),
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A barra de baixo do console, na zona do polegar: o botão grande que faz a fila andar e, quando
/// há alguém na cadeira, o "Não veio".
///
/// O botão diz quem será chamado antes do toque. Não há confirmação: o que protege de um engano
/// é o Desfazer que aparece em seguida.
class ShopConsoleActionBar extends ConsumerWidget {
  const ShopConsoleActionBar({required this.shopId, required this.barberId, super.key});

  final String shopId;
  final String barberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = (shopId: shopId, barberId: barberId);
    final queueState = ref.watch(publicQueueProvider(shopId));
    final console = ref.watch(consoleControllerProvider(key));
    final controller = ref.read(consoleControllerProvider(key).notifier);

    // Só com a fila em dia, como o corpo da tela: com erro de leitura o último dado conhecido
    // pode estar velho, e o botão prometeria chamar quem já não é o próximo.
    if (queueState is! AsyncData<PublicQueue?>) return const SizedBox.shrink();
    final queue = queueState.value;

    final status = queue?.statusOf(barberId) ?? BarberStatus.off;
    final serving = queue?.servedBy(barberId);
    if (!_showsActionBar(status, serving)) return const SizedBox.shrink();
    // Em pausa o barbeiro termina quem está na cadeira, mas não chama mais ninguém.
    final next = status == BarberStatus.available ? queue?.nextFor(barberId) : null;
    final failure = console.failure;

    VoidCallback? whenFree(VoidCallback action) => console.busy ? null : action;

    final (label, subtitle, onMain) = switch ((next, serving)) {
      (final WaitingTicket next, _) => (
        l10n.consoleNextAction,
        l10n.consoleNextWho(next.number, next.label),
        whenFree(controller.callNext),
      ),
      (null, ServingTicket()) => (
        l10n.consoleFinishAction,
        null,
        whenFree(controller.finishCurrent),
      ),
      // Pode haver gente esperando por outro barbeiro: o que não há é quem este possa chamar.
      (null, null) => (l10n.consoleNobodyToCall, null, null),
    };
    final pendingLabel = switch (console.pending) {
      ConsoleAction.callNext => l10n.consoleCalling,
      ConsoleAction.finish || ConsoleAction.noShow => l10n.consoleFinishing,
      ConsoleAction.undo => l10n.consoleUndoing,
      _ => null,
    };

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Reserva a altura da barra de progresso para os botões não pularem.
            SizedBox(
              height: Insets.xs,
              child: pendingLabel == null
                  ? null
                  : LinearProgressIndicator(semanticsLabel: pendingLabel),
            ),
            Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (failure != null) ...[
                        _FailureNotice(failure: failure),
                        const SizedBox(height: Insets.sm),
                      ],
                      if (serving != null) ...[
                        // Do lado oposto ao "Desfazer" do aviso, que aparece logo acima: quem
                        // mira um não acerta o outro.
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, Insets.touchTarget),
                            ),
                            // Com gente esperando, quem não veio dá lugar ao seguinte; sem
                            // ninguém, só libera a cadeira.
                            onPressed: whenFree(
                              () => next != null
                                  ? controller.callNext(noShow: true)
                                  : controller.finishCurrent(noShow: true),
                            ),
                            icon: const Icon(Icons.person_off_outlined),
                            label: Text(
                              l10n.consoleNoShowAction,
                              semanticsLabel: l10n.consoleNoShowWho(serving.number, serving.label),
                            ),
                          ),
                        ),
                        const SizedBox(height: Insets.md),
                      ],
                      FilledButton(
                        key: const ValueKey('console-main-action'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(Insets.primaryActionHeight),
                          // O botão inerte ainda informa ("Chamando…", "Ninguém para chamar"):
                          // precisa continuar legível.
                          disabledBackgroundColor: scheme.surfaceContainerHighest,
                          disabledForegroundColor: scheme.onSurfaceVariant,
                        ),
                        onPressed: onMain,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              pendingLabel ?? label,
                              textAlign: TextAlign.center,
                              // Sem cor própria: herda a do botão, habilitado ou não.
                              style: TextStyle(
                                fontSize: theme.textTheme.headlineSmall?.fontSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subtitle != null && pendingLabel == null)
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: theme.textTheme.titleMedium?.fontSize,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
