import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/core/widgets/site_shell.dart';
import 'package:proximo/features/queue/domain/eta.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/presentation/widgets/queue_sections.dart';
import 'package:proximo/features/shop/domain/shop_slug.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Tela inicial: o cliente digita o código da barbearia (ou chega direto pelo QR Code)
/// e o barbeiro entra no console.
///
/// No celular é uma coluna única e direta; em telas largas vira a página de apresentação do
/// site, com navegação no topo, um exemplo de fila e os passos de como funciona.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Mantém o formulário (texto digitado, foco, erro) quando a janela cruza o breakpoint e o
  /// layout troca.
  final _codeFormKey = GlobalKey<_JoinByCodeFormState>();

  @override
  Widget build(BuildContext context) => Breakpoints.isWide(context)
      ? _WideHome(codeFormKey: _codeFormKey)
      : _CompactHome(codeFormKey: _codeFormKey);
}

class _CompactHome extends StatelessWidget {
  const _CompactHome({required this.codeFormKey});

  final GlobalKey<_JoinByCodeFormState> codeFormKey;

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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l10n.homeJoinTitle, style: theme.textTheme.titleLarge),
                        const SizedBox(height: Insets.md),
                        _JoinByCodeForm(key: codeFormKey, inline: false),
                      ],
                    ),
                  ),
                ),
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

class _WideHome extends StatefulWidget {
  const _WideHome({required this.codeFormKey});

  final GlobalKey<_JoinByCodeFormState> codeFormKey;

  @override
  State<_WideHome> createState() => _WideHomeState();
}

class _WideHomeState extends State<_WideHome> {
  final _howItWorksKey = GlobalKey();
  final _howItWorksFocus = FocusNode(debugLabel: 'como-funciona');

  @override
  void dispose() {
    _howItWorksFocus.dispose();
    super.dispose();
  }

  /// Rola até "Como funciona" e leva o foco para lá, para o teclado e o leitor de tela
  /// acompanharem. Sem animação para quem pediu menos movimento no sistema.
  Future<void> _showHowItWorks() async {
    final target = _howItWorksKey.currentContext;
    if (target == null) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    await Scrollable.ensureVisible(
      target,
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    if (mounted) _howItWorksFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SitePage(
      actions: [
        TextButton(onPressed: _showHowItWorks, child: Text(l10n.homeHowItWorksTitle)),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(0, Insets.touchTarget)),
          onPressed: () => context.goNamed(AppRoutes.console),
          child: Text(l10n.homeBarberTitle),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      headingLevel: 1,
                      child: Text(l10n.homeHeroTitle, style: theme.textTheme.displayMedium),
                    ),
                    const SizedBox(height: Insets.md),
                    Text(
                      l10n.homeHeroSubtitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Insets.xl),
                    _JoinByCodeForm(key: widget.codeFormKey, inline: true),
                  ],
                ),
              ),
              const SizedBox(width: Insets.xxl),
              const Expanded(flex: 5, child: _ExampleQueue()),
            ],
          ),
          const SizedBox(height: Insets.xxl),
          Focus(
            focusNode: _howItWorksFocus,
            child: Semantics(
              key: _howItWorksKey,
              header: true,
              headingLevel: 2,
              child: Text(l10n.homeHowItWorksTitle, style: theme.textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: Insets.lg),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StepCard(
                    number: 1,
                    icon: Icons.qr_code_2_rounded,
                    title: l10n.homeStepScanTitle,
                    body: l10n.homeStepScanBody,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: _StepCard(
                    number: 2,
                    icon: Icons.groups_rounded,
                    title: l10n.homeStepTrackTitle,
                    body: l10n.homeStepTrackBody,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: _StepCard(
                    number: 3,
                    icon: Icons.content_cut_rounded,
                    title: l10n.homeStepArriveTitle,
                    body: l10n.homeStepArriveBody,
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

/// Campo do código da barbearia com o botão "Ver fila" e a explicação do que é o código:
/// empilhado no celular, campo e botão lado a lado no layout de site.
class _JoinByCodeForm extends StatefulWidget {
  const _JoinByCodeForm({required this.inline, super.key});

  final bool inline;

  @override
  State<_JoinByCodeForm> createState() => _JoinByCodeFormState();
}

class _JoinByCodeFormState extends State<_JoinByCodeForm> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final code = normalizeShopCode(_controller.text);
    final error = code.isEmpty
        ? l10n.homeCodeEmpty
        : (isValidShopSlug(code) ? null : l10n.homeCodeInvalid);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    context.goNamed(AppRoutes.joinQueue, pathParameters: {'slug': code});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final field = TextField(
      controller: _controller,
      autocorrect: false,
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        labelText: l10n.homeJoinHint,
        hintText: l10n.homeCodeExample,
        errorText: _error,
        errorMaxLines: 3,
        prefixIcon: const Icon(Icons.storefront_rounded),
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _submit(),
    );
    final help = Text(
      l10n.homeCodeHelp,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );

    if (!widget.inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: Insets.md),
          FilledButton(onPressed: _submit, child: Text(l10n.homeJoinAction)),
          const SizedBox(height: Insets.md),
          help,
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campo e botão não são texto para selecionar (o layout de site permite seleção).
          SelectionContainer.disabled(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field),
                const SizedBox(width: Insets.sm),
                FilledButton(
                  // O tema estica os botões na largura toda; ao lado do campo ele ocupa só o texto.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, Insets.controlHeight)),
                  onPressed: _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.md),
                    child: Text(l10n.homeJoinAction),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          help,
        ],
      ),
    );
  }
}

/// Uma fila de mentira, montada com os mesmos blocos da fila real, para mostrar o que o cliente
/// vai ver. A moldura e o selo deixam claro que é uma ilustração, e o leitor de tela a recebe
/// como um item só, não como dados ao vivo.
class _ExampleQueue extends StatelessWidget {
  const _ExampleQueue();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final names = [l10n.homeExampleFirst, l10n.homeExampleSecond, l10n.homeExampleThird];
    final queue = PublicQueue(
      shopId: 'exemplo',
      shopName: '',
      dateKey: '',
      entry: const EntryState(open: true, eta: EstimatedEta(Duration(minutes: 55))),
      barbers: const [],
      nowServing: const [],
      waiting: [
        for (final (index, name) in names.indexed)
          WaitingTicket(
            ticketId: 'exemplo-$index',
            number: index + 12,
            label: name,
            serviceId: 'corte',
            position: index + 1,
            eta: EstimatedEta(Duration(minutes: index * 25)),
          ),
      ],
      version: 0,
      updatedAt: DateTime(2026),
    );

    return Semantics(
      container: true,
      label: l10n.homeExampleSemantics,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(Insets.radiusLarge),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(Insets.radius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Insets.md,
                        vertical: Insets.xs,
                      ),
                      child: Text(
                        l10n.homeExampleLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Insets.md),
                QueueSummaryCard(queue: queue),
                const SizedBox(height: Insets.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
                    child: WaitingListSection(queue: queue),
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

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text('$number')),
                const SizedBox(width: Insets.md),
                Icon(icon, size: Insets.xl, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: Insets.md),
            Semantics(
              header: true,
              headingLevel: 3,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              body,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
