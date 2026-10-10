import 'dart:async';

import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/auth/domain/auth_repository.dart';

/// Barbeiro do seed, já vinculado à barbearia de demonstração nos testes.
const barberZe = AppUser(uid: 'barbeiro-ze', isAnonymous: false, displayName: 'Zé');

/// [AuthRepository] em memória. Como o Firebase, entrega o usuário atual a quem começa a observar.
final class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? signedInAs, this.accounts = const {}}) : _user = signedInAs;

  /// Contas aceitas no login: e-mail → (senha, usuário).
  final Map<String, ({String password, AppUser user})> accounts;

  /// Quando definido, o login só responde depois que o teste completar este [Completer].
  Completer<void>? signInGate;

  /// Falha devolvida pelo próximo login, no lugar da checagem de [accounts].
  Failure? nextSignInFailure;

  final signInAttempts = <String>[];
  final _changes = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<Result<AppUser>> ensureSignedIn() async {
    final user = _user ?? const AppUser(uid: 'anonimo', isAnonymous: true);
    _set(user);
    return Ok(user);
  }

  @override
  Future<Result<AppUser>> signInWithEmail({required String email, required String password}) async {
    signInAttempts.add(email.trim());
    await signInGate?.future;

    final failure = nextSignInFailure;
    if (failure != null) {
      nextSignInFailure = null;
      return Err(failure);
    }
    final account = accounts[email.trim()];
    if (account == null || account.password != password) return const Err(PermissionFailure());
    _set(account.user);
    return Ok(account.user);
  }

  @override
  Future<void> signOut() async => _set(null);

  void _set(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  Future<void> dispose() => _changes.close();
}
