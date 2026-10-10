import 'package:proximo/core/json/json.dart';

/// Portas mínimas para o backend. As camadas de dados dependem destas funções, não dos SDKs,
/// o que permite testá-las sem Firebase (Dependency Inversion).

/// Invoca uma Cloud Function callable e devolve o `data` da resposta.
/// Erros do servidor chegam como [CallableException].
typedef CallableInvoker = Future<Object?> Function(String name, JsonMap payload);

/// Observa um documento; emite `null` quando ele não existe.
typedef DocumentWatcher = Stream<JsonMap?> Function(String path);

/// Erro de uma callable, já independente do SDK.
final class CallableException implements Exception {
  const CallableException(this.code, {this.message, this.details});

  /// Código HTTPS do Firebase (`failed-precondition`, `unavailable`, …).
  final String code;
  final String? message;
  final Object? details;

  @override
  String toString() => 'CallableException($code, $message)';
}
