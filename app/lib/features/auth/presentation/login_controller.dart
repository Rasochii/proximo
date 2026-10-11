import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/features/auth/presentation/auth_providers.dart';

@immutable
final class LoginState {
  const LoginState({this.submitting = false, this.failure});

  final bool submitting;

  /// Falha da última tentativa; some ao tentar de novo.
  final Failure? failure;

  @override
  bool operator ==(Object other) =>
      other is LoginState && other.submitting == submitting && other.failure == failure;

  @override
  int get hashCode => Object.hash(submitting, failure);
}

/// Login da equipe por e-mail e senha. O sucesso aparece pelo [authStateProvider].
final loginControllerProvider = NotifierProvider.autoDispose<LoginController, LoginState>(
  LoginController.new,
);

class LoginController extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  Future<void> signIn({required String email, required String password}) async {
    if (state.submitting) return;
    state = const LoginState(submitting: true);
    final result = await ref
        .read(authRepositoryProvider)
        .signInWithEmail(email: email, password: password);
    if (!ref.mounted) return;
    state = LoginState(failure: result.failureOrNull);
  }
}
