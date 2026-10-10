/// Ambiente de execução, definido em tempo de build:
///
/// ```sh
/// flutter run --dart-define=ENV=emulator               # padrão: emuladores locais
/// flutter run --dart-define=ENV=emulator --dart-define=EMULATOR_HOST=192.168.0.10
/// flutter run --dart-define=ENV=prod                   # projeto Firebase real
/// ```
enum AppEnv {
  emulator,
  prod;

  static AppEnv get current => switch (const String.fromEnvironment('ENV', defaultValue: 'emulator')) {
    'prod' => AppEnv.prod,
    _ => AppEnv.emulator,
  };

  bool get usesEmulators => this == AppEnv.emulator;
}

/// Configurações fixas compartilhadas com o backend.
abstract final class AppConfig {
  /// Mesmo valor de `REGION` em `functions/src/firebase/app.ts`.
  static const functionsRegion = 'southamerica-east1';

  /// Projeto usado nos emuladores (`projetos demo-*` não acessam recursos reais).
  static const emulatorProjectId = 'demo-proximo';

  /// Host dos emuladores. Vazio = automático (10.0.2.2 no emulador Android, localhost no resto).
  static const emulatorHostOverride = String.fromEnvironment('EMULATOR_HOST');
}
