import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:proximo/core/config/app_env.dart';
import 'package:proximo/core/firebase/firebase_options.dart';

/// Inicializa o Firebase conforme o [AppEnv] e, nos emuladores, conecta todos os serviços locais.
abstract final class FirebaseInitializer {
  static Future<void> initialize(AppEnv env) async {
    switch (env) {
      case AppEnv.emulator:
        await Firebase.initializeApp(options: _emulatorOptions);
        await _connectEmulators();
      case AppEnv.prod:
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  }

  /// Opções fictícias: aceitas pelos SDKs e suficientes para falar com os emuladores.
  static FirebaseOptions get _emulatorOptions => FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: kIsWeb
        ? '1:000000000000:web:0000000000000000000000'
        : '1:000000000000:${defaultTargetPlatform.name.toLowerCase()}:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: AppConfig.emulatorProjectId,
  );

  static Future<void> _connectEmulators() async {
    final host = _emulatorHost;
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(
      region: AppConfig.functionsRegion,
    ).useFunctionsEmulator(host, 5001);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  }

  static String get _emulatorHost {
    if (AppConfig.emulatorHostOverride.isNotEmpty) return AppConfig.emulatorHostOverride;
    // O emulador Android enxerga a máquina host por 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return '10.0.2.2';
    return 'localhost';
  }
}
