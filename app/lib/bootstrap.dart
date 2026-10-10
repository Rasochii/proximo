import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/config/app_env.dart';
import 'package:proximo/core/config/provider_retry.dart';
import 'package:proximo/core/firebase/firebase_initializer.dart';

/// Ponto único de inicialização: erros globais, Firebase e escopo do Riverpod.
Future<void> bootstrap(Widget Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack, name: 'FlutterError');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    log('$error', stackTrace: stack, name: 'Uncaught');
    return true;
  };

  final env = AppEnv.current;
  await FirebaseInitializer.initialize(env);
  if (kDebugMode) log('Próximo! iniciado no ambiente ${env.name}', name: 'bootstrap');

  runApp(ProviderScope(retry: noAutomaticRetry, child: builder()));
}
