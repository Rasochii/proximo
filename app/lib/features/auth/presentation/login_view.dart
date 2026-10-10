import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/l10n/failure_messages.dart';
import 'package:proximo/core/router/app_router.dart';
import 'package:proximo/core/theme/app_theme.dart';
import 'package:proximo/features/auth/presentation/login_controller.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Formulário de login da equipe (e-mail e senha). Quem decide o que vem depois é a tela que o
/// hospeda, observando o usuário logado.
class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  var _showPassword = false;

  /// Depois da primeira tentativa, os avisos somem assim que o campo é corrigido.
  var _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    ref.read(loginControllerProvider.notifier).signIn(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(loginControllerProvider);
    final failure = state.failure;

    // Login recusado: devolve o foco à senha, já selecionada, para redigitar sem tocar no campo.
    // Os campos não são travados durante o envio: no navegador, alternar `readOnly` ou `enabled`
    // deixa o campo sem receber o teclado depois. Um segundo envio já é ignorado pelo controller.
    ref.listen(loginControllerProvider, (previous, next) {
      if (next.failure == null || !(previous?.submitting ?? false)) return;
      _passwordFocus.requestFocus();
      _password.selection = TextSelection(baseOffset: 0, extentOffset: _password.text.length);
    });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Insets.maxContentWidth),
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(Insets.lg),
              shrinkWrap: true,
              children: [
                Semantics(
                  header: true,
                  child: Text(l10n.loginTitle, style: theme.textTheme.headlineMedium),
                ),
                const SizedBox(height: Insets.sm),
                Text(l10n.loginSubtitle, style: theme.textTheme.bodyLarge),
                const SizedBox(height: Insets.lg),
                TextFormField(
                  controller: _email,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: l10n.loginEmailLabel,
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? l10n.loginEmailRequired : null,
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: l10n.loginPasswordLabel,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? l10n.loginHidePassword : l10n.loginShowPassword,
                      icon: Icon(
                        _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty ? l10n.loginPasswordRequired : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (failure != null) ...[
                  const SizedBox(height: Insets.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message(l10n, failure),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                const SizedBox(height: Insets.lg),
                FilledButton(
                  onPressed: state.submitting ? null : _submit,
                  child: state.submitting
                      ? SizedBox.square(
                          dimension: Insets.lg,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            semanticsLabel: l10n.loginSubmitting,
                          ),
                        )
                      : Text(l10n.loginAction),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  l10n.loginHelp,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Insets.sm),
                TextButton(
                  onPressed: () => context.goNamed(AppRoutes.home),
                  child: Text(l10n.backToHome),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// No login, "sem permissão" significa credenciais erradas.
  static String _message(AppLocalizations l10n, Failure failure) => switch (failure) {
    PermissionFailure() || UnauthenticatedFailure() => l10n.loginInvalidCredentials,
    _ => l10n.failureMessage(failure),
  };
}
