import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/core/widgets/site_shell.dart';
import 'package:proximo/features/auth/domain/auth_repository.dart';
import 'package:proximo/features/auth/domain/staff_membership.dart';
import 'package:proximo/features/auth/presentation/auth_providers.dart';
import 'package:proximo/features/auth/presentation/login_view.dart';
import 'package:proximo/features/shop/presentation/shop_providers.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Console do barbeiro. Decide o que mostrar pelo usuário logado: login, aviso de conta sem
/// barbearia ou o console da barbearia dele.
///
/// F3/T2: acesso e vínculo. A fila e o "Próximo!" chegam nas próximas tarefas da F3.
class ConsolePage extends ConsumerWidget {
  const ConsolePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authStateProvider);
    final membership = ref.watch(staffMembershipProvider);
    Future<void> signOut() => ref.read(authRepositoryProvider).signOut();

    return switch ((auth, membership)) {
      (AsyncError(), _) => _ConsoleScaffold(
        child: _MessageView(
          icon: Icons.cloud_off_rounded,
          message: l10n.genericError,
          actions: [
            FilledButton.tonal(
              onPressed: () => ref.invalidate(authStateProvider),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      // Cliente (conta anônima) ou ninguém logado: o console exige a conta da equipe.
      (AsyncData(value: null), _) ||
      (AsyncData(value: AppUser(isAnonymous: true)), _) => const _ConsoleScaffold(
        child: LoginView(),
      ),
      (AsyncData(), AsyncError()) => _ConsoleScaffold(
        accountAction: _SignOutButton(onSignOut: signOut),
        child: _MessageView(
          icon: Icons.cloud_off_rounded,
          message: l10n.genericError,
          actions: [
            FilledButton.tonal(
              onPressed: () => ref.invalidate(staffMembershipProvider),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
      (AsyncData(), AsyncData(value: null)) => _ConsoleScaffold(
        accountAction: _SignOutButton(onSignOut: signOut),
        child: _MessageView(
          icon: Icons.storefront_outlined,
          message: l10n.consoleNoMembership,
          actions: [
            // A saída útil é trocar de conta: voltar ao início continuaria com a conta errada.
            FilledButton(onPressed: signOut, child: Text(l10n.consoleSwitchAccountAction)),
            TextButton(
              onPressed: () => context.goNamed(AppRoutes.home),
              child: Text(l10n.backToHome),
            ),
          ],
        ),
      ),
      (AsyncData(), AsyncData(value: final StaffMembership staff)) => _ShopConsole(
        shopId: staff.shopId,
        onSignOut: signOut,
      ),
      // Equipe logada esperando o vínculo: já pode sair se a espera não terminar.
      (AsyncData(), _) => _ConsoleScaffold(
        accountAction: _SignOutButton(onSignOut: signOut),
        child: const _LoadingView(),
      ),
      _ => const _ConsoleScaffold(child: _LoadingView()),
    };
  }
}

/// Console de uma barbearia. Por enquanto só identifica a barbearia e permite sair.
class _ShopConsole extends ConsumerWidget {
  const _ShopConsole({required this.shopId, required this.onSignOut});

  final String shopId;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shop = ref.watch(shopProvider(shopId));

    return _ConsoleScaffold(
      title: shop.value?.name,
      brandLeadsHome: false,
      // No console em uso, sair fica a dois toques: um esbarrão não derruba a sessão no balcão.
      accountAction: _AccountMenu(onSignOut: onSignOut),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Text(l10n.comingSoon('F3'), textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _ConsoleScaffold extends StatelessWidget {
  const _ConsoleScaffold({
    required this.child,
    this.title,
    this.accountAction,
    this.brandLeadsHome = true,
  });

  final Widget child;

  /// Nome da barbearia; sem ele, o título genérico do console.
  final String? title;

  /// Botão ou menu de conta na barra (ausente quando ninguém da equipe está logado).
  final Widget? accountAction;

  /// No console em uso a marca do cabeçalho não é um link: um esbarrão não tira o barbeiro da tela.
  final bool brandLeadsHome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = this.title ?? l10n.consoleTitle;

    final wide = Breakpoints.isWide(context);

    // Telas largas trocam a barra do app pelo cabeçalho do site. O conteúdo fica sempre no mesmo
    // lugar da árvore (a chave garante), para um formulário não perder o que foi digitado quando
    // a janela cruza o breakpoint.
    return Scaffold(
      appBar: wide ? null : AppBar(title: Text(title), actions: [?accountAction]),
      body: SafeArea(
        child: Column(
          children: [
            if (wide)
              SiteHeader(
                title: title,
                actions: [?accountAction],
                brandLeadsHome: brandLeadsHome,
              ),
            Expanded(key: const ValueKey('console-body'), child: child),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).signOutAction,
      icon: const Icon(Icons.logout_rounded),
      onPressed: onSignOut,
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<void>(
      tooltip: l10n.accountMenuTooltip,
      icon: const Icon(Icons.account_circle_outlined),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: onSignOut,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout_rounded),
            title: Text(l10n.signOutAction),
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(semanticsLabel: AppLocalizations.of(context).loadingLabel),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.icon, required this.message, required this.actions});

  final IconData icon;
  final String message;

  /// Da mais importante para a menos importante, empilhadas.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(Insets.lg),
          shrinkWrap: true,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: Insets.md),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.lg),
            for (final action in actions) ...[action, const SizedBox(height: Insets.sm)],
          ],
        ),
      ),
    );
  }
}
