import 'dart:async';

import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/json/json.dart';

/// Cloud Functions de mentira: registra cada chamada e responde pelo [handler] do teste.
///
/// Sem [handler], toda chamada dá certo e devolve um objeto vazio. Para simular a recusa de uma
/// regra, lance [domainError]; para segurar a resposta, use [gate].
final class FakeCallables {
  FakeCallables([this.handler]);

  FutureOr<Object?> Function(String name, JsonMap payload)? handler;

  /// Quando definido, cada chamada só responde depois que o teste completar este [Completer].
  Completer<void>? gate;

  final calls = <({String name, JsonMap payload})>[];

  Future<Object?> invoke(String name, JsonMap payload) async {
    calls.add((name: name, payload: payload));
    await gate?.future;
    return await handler?.call(name, payload) ?? const <String, Object?>{};
  }

  /// O erro que o servidor devolve quando uma regra da fila recusa o comando.
  static CallableException domainError(String code) =>
      CallableException('failed-precondition', details: {'code': code});
}
