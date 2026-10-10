import 'package:firebase_core/firebase_core.dart';

/// Placeholder das opções do projeto Firebase real.
///
/// Será SOBRESCRITO por `flutterfire configure --out=lib/core/firebase/firebase_options.dart`
/// quando o projeto de produção for criado (ADR 0006). Até lá, use `--dart-define=ENV=emulator`.
abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
    'Projeto Firebase de produção ainda não configurado. '
    'Rode `flutterfire configure` ou use --dart-define=ENV=emulator.',
  );
}
