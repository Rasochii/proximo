import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/core/widgets/site_shell.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/presentation/queue_providers.dart';
import 'package:proximo/features/queue/presentation/widgets/queue_sections.dart';
import 'package:proximo/features/shop/domain/shop.dart';
import 'package:proximo/features/shop/presentation/shop_providers.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Fila de uma barbearia aberta pelo link/QR Code (`/b/:slug`), atualizada em tempo real.
///
/// F2: visualização ao vivo da fila pública. O formulário de entrada chega na F4.
///
/// No celular é uma coluna única; em telas largas usa o layout de site, com o resumo e a lista
/// lado a lado. A troca de layout refaz a árvore abaixo desta página: estado que precisa
/// sobreviver a um redimensionamento (como o `requestId` de uma entrada na fila) deve morar em
/// providers, não em `State` de widgets daqui para baixo.
class JoinQueuePage extends ConsumerWidget {
  const JoinQueuePage({required this.slug, super.key});

  /// O id do documento da barbearia é o próprio slug.
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shop = ref.watch(shopProvider(slug));
    final queue = ref.watch(publicQueueProvider(slug));
    final wide = Breakpoints.isWide(context);
    final knownShop = shop.value;

    final content = switch ((shop, queue)) {
      (AsyncError(), _) || (_, AsyncError()) => _MessageView(
        icon: Icons.cloud_off_rounded,
        isError: true,
        message: l10n.genericError,
        action: FilledButton.tonal(
          onPressed: () {
            ref
              ..invalidate(shopProvider(slug))
              ..invalidate(publicQueueProvider(slug));
          },
          child: Text(l10n.retry),
        ),
      ),
      (AsyncData(value: null), _) => _MessageView(
        icon: Icons.storefront_outlined,
        message: l10n.shopNotFound,
        action: FilledButton.tonal(
          onPressed: () => context.goNamed(AppRoutes.home),
          child: Text(l10n.shopNotFoundAction),
        ),
      ),
      (AsyncData(value: final Shop _), AsyncData(value: null)) => _MessageView(
        icon: Icons.schedule_rounded,
        message: l10n.queueNotOpenedYet,
      ),
      (AsyncData(value: final Shop _), AsyncData(value: final PublicQueue live)) =>
        wide ? _WideQueueView(queue: live) : _CompactQueueView(queue: live),
      _ => Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: CircularProgressIndicator(semanticsLabel: l10n.loadingLabel),
        ),
      ),
    };

    if (wide) {
      return SitePage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // O nome aparece em todos os estados, como a barra de título no celular.
            if (knownShop != null) ...[
              Semantics(
                header: true,
                headingLevel: 1,
                child: Text(knownShop.name, style: Theme.of(context).textTheme.displaySmall),
              ),
              const SizedBox(height: Insets.xl),
            ],
            content,
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(knownShop?.name ?? slug)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Celular: tudo empilhado, com a lista construída sob demanda.
class _CompactQueueView extends StatelessWidget {
  const _CompactQueueView({required this.queue});

  final PublicQueue queue;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        QueueSummaryCard(queue: queue),
        const SizedBox(height: Insets.lg),
        NowServingSection(tickets: queue.nowServing),
        if (queue.waiting.isNotEmpty) ...[
          const SizedBox(height: Insets.lg),
          QueueSectionTitle(AppLocalizations.of(context).queueWaitingListTitle),
          for (final ticket in queue.waiting) WaitingTicketTile(ticket: ticket),
        ],
      ],
    );
  }
}

/// Telas largas: o resumo à esquerda e a fila à direita.
class _WideQueueView extends StatelessWidget {
  const _WideQueueView({required this.queue});

  final PublicQueue queue;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QueueSummaryCard(queue: queue),
              const SizedBox(height: Insets.lg),
              NowServingSection(tickets: queue.nowServing),
            ],
          ),
        ),
        const SizedBox(width: Insets.xl),
        Expanded(
          flex: 6,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: WaitingListSection(queue: queue),
            ),
          ),
        ),
      ],
    );
  }
}

/// Estado sem fila para mostrar: ícone, mensagem e, quando há o que fazer, uma ação.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    this.action,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final Widget? action;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = this.action;

    return Center(
      // No layout de site não há coluna estreita em volta: sem este limite o botão do tema,
      // que ocupa toda a largura, atravessaria a página.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: isError ? theme.colorScheme.error : theme.colorScheme.outline,
              ),
              const SizedBox(height: Insets.md),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              if (action != null) ...[
                const SizedBox(height: Insets.md),
                // Rótulo de botão não é texto para selecionar (o layout de site permite seleção).
                SelectionContainer.disabled(child: action),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
