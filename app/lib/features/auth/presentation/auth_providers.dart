import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/features/auth/data/firebase_auth_repository.dart';
import 'package:proximo/features/auth/domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(ref.watch(firebaseAuthProvider)),
);

/// Usuário logado em tempo real (`null` = ninguém logado).
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);
