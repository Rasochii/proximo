import 'package:firebase_auth/firebase_auth.dart';
import 'package:meta/meta.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/auth/domain/auth_repository.dart';

final class FirebaseAuthRepository implements AuthRepository {
  const FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<Result<AppUser>> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return Ok(_toAppUser(existing)!);
    return _guard(() async => (await _auth.signInAnonymously()).user);
  }

  @override
  Future<Result<AppUser>> signInWithEmail({required String email, required String password}) =>
      _guard(
        () async =>
            (await _auth.signInWithEmailAndPassword(email: email.trim(), password: password)).user,
      );

  @override
  Future<void> signOut() => _auth.signOut();

  Future<Result<AppUser>> _guard(Future<User?> Function() action) async {
    try {
      final user = _toAppUser(await action());
      return user == null ? const Err(UnauthenticatedFailure()) : Ok(user);
    } on FirebaseAuthException catch (error) {
      return Err(failureFromAuthCode(error.code));
    } on Exception catch (error) {
      // Qualquer outra falha do SDK vira Failure: quem chama nunca fica esperando para sempre.
      return Err(UnexpectedFailure(error));
    }
  }

  /// Traduz o código de erro do Firebase Auth para uma [Failure] que a UI sabe apresentar.
  @visibleForTesting
  static Failure failureFromAuthCode(String code) => switch (code) {
    'network-request-failed' => const NetworkFailure(),
    // Bloqueio temporário por excesso de tentativas: insistir só prolonga a espera.
    'too-many-requests' => const QueueRuleFailure(QueueErrorCode.rateLimited),
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => const PermissionFailure(),
    _ => UnexpectedFailure(code),
  };

  static AppUser? _toAppUser(User? user) => user == null
      ? null
      : AppUser(uid: user.uid, isAnonymous: user.isAnonymous, displayName: user.displayName);
}
