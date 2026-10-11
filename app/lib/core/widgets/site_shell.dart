import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Cabeçalho do layout de site: a marca leva ao início, [title] identifica a página e
/// [actions] ficam à direita.
class SiteHeader extends StatelessWidget {
  const SiteHeader({this.title, this.actions = const [], this.brandLeadsHome = true, super.key});

  final String? title;
  final List<Widget> actions;

  /// Com  a marca é só texto. Usado onde um toque acidental não pode tirar a pessoa da
  /// tela, como no console em uso no balcão.
  final bool brandLeadsHome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = this.title;
    final brand = Text(
      l10n.appTitle,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Center(
        // Ocupa só a própria altura, mesmo quando o pai oferece a tela inteira.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Insets.maxSiteWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.sm),
            child: Row(
              children: [
                if (brandLeadsHome)
                  Tooltip(
                    message: l10n.backToHome,
                    child: TextButton(
                      onPressed: () => context.goNamed(AppRoutes.home),
                      child: brand,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                    child: brand,
                  ),
                if (title != null) ...[
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  for (final action in actions) ...[const SizedBox(width: Insets.sm), action],
                ] else
                  // Sem título, as ações ficam com todo o espaço que sobra, alinhadas à direita.
                  // Se nem assim couberem (letra muito grande), encolhem em vez de estourar.
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final action in actions) ...[
                              const SizedBox(width: Insets.sm),
                              action,
                            ],
                          ],
                        ),
                      ),
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

/// Rodapé do layout de site.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Center(
        // Ocupa só a própria altura, mesmo quando o pai oferece a tela inteira.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Insets.maxSiteWidth),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              heightFactor: 1,
              child: Text(
                AppLocalizations.of(context).siteFooterTagline,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Página no layout de site (telas largas): cabeçalho fixo, conteúdo centralizado com largura
/// máxima e rodapé no fim da rolagem. O texto pode ser selecionado, como num site.
///
/// Telas estreitas não usam esta moldura; veja [Breakpoints.isWide].
class SitePage extends StatelessWidget {
  const SitePage({required this.child, this.title, this.actions = const [], super.key});

  final Widget child;
  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SiteHeader(title: title, actions: actions),
            Expanded(
              child: SelectionArea(
                child: CustomScrollView(
                  // Liga a rolagem às teclas (PageDown, setas) também no desktop.
                  primary: true,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: Insets.maxSiteWidth),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Insets.lg,
                              vertical: Insets.xxl,
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Align(alignment: Alignment.bottomCenter, child: SiteFooter()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
