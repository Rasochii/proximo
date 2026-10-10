import 'package:meta/meta.dart';
import 'package:proximo/core/result/result.dart';

@immutable
final class AppUser {
  const AppUser({required this.uid, required this.isAnonymous, this.displayName});

  final String uid;

  /// Cliente que entrou só com o nome (conta anônima, pode ser promovida depois).
  final bool isAnonymous;
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.isAnonymous == isAnonymous &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, isAnonymous, displayName);
}

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Garante uma sessão: reaproveita a atual ou cria uma conta anônima (cliente "só com o nome").
  Future<Result<AppUser>> ensureSignedIn();

  /// Login da equipe (barbeiro/dono).
  Future<Result<AppUser>> signInWithEmail({required String email, required String password});

  Future<void> signOut();
}
