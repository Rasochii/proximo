import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/features/auth/data/firebase_auth_repository.dart';
import 'package:proximo/features/auth/data/firestore_staff_repository.dart';
import 'package:proximo/features/auth/domain/auth_repository.dart';
import 'package:proximo/features/auth/domain/staff_membership.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(ref.watch(firebaseAuthProvider)),
);

/// Usuário logado em tempo real (`null` = ninguém logado).
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => FirestoreStaffRepository(ref.watch(documentWatcherProvider)),
);

/// Barbearia do usuário logado; `null` para clientes (conta anônima), sem login ou sem vínculo.
final staffMembershipProvider = StreamProvider.autoDispose<StaffMembership?>((ref) {
  final user = ref.watch(authStateProvider.select((auth) => auth.value));
  if (user == null || user.isAnonymous) return Stream.value(null);
  return ref.watch(staffRepositoryProvider).watchMembership(user.uid);
});
