import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/config/app_env.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/ids/request_id.dart';
import 'package:proximo/core/json/json.dart';

/// Composição das dependências do Firebase. Em testes, sobrescreva [documentWatcherProvider],
/// [callableInvokerProvider] e [requestIdGeneratorProvider] — nada abaixo deles precisa de Firebase.

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion),
);

final documentWatcherProvider = Provider<DocumentWatcher>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return (path) => firestore.doc(path).snapshots().map((snapshot) => snapshot.data());
});

final callableInvokerProvider = Provider<CallableInvoker>((ref) {
  final functions = ref.watch(functionsProvider);
  return (name, payload) async {
    try {
      final result = await functions.httpsCallable(name).call<Object?>(payload);
      return normalizeJson(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw CallableException(error.code, message: error.message, details: normalizeJson(error.details));
    }
  };
});

final requestIdGeneratorProvider = Provider<RequestIdGenerator>((ref) => uuidV4RequestId);
