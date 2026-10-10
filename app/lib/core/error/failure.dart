import 'package:meta/meta.dart';
import 'package:proximo/core/error/queue_error_code.dart';

/// Falhas esperadas que a UI sabe apresentar. Nunca carregam dados pessoais.
@immutable
sealed class Failure implements Exception {
  const Failure();
}

/// Regra de negócio recusou a ação (ex.: fila fechada, já está em uma fila).
final class QueueRuleFailure extends Failure {
  const QueueRuleFailure(this.code, {this.retryAfter});

  final QueueErrorCode code;

  /// Para `rateLimited`: quanto tempo esperar antes de tentar de novo.
  final Duration? retryAfter;

  @override
  bool operator ==(Object other) =>
      other is QueueRuleFailure && other.code == code && other.retryAfter == retryAfter;

  @override
  int get hashCode => Object.hash(code, retryAfter);

  @override
  String toString() => 'QueueRuleFailure(${code.wire})';
}

/// Sem conexão ou servidor indisponível (já foram feitas novas tentativas).
final class NetworkFailure extends Failure {
  const NetworkFailure();
}

/// Usuário não autenticado.
final class UnauthenticatedFailure extends Failure {
  const UnauthenticatedFailure();
}

/// Usuário autenticado sem permissão (ex.: cliente tentando chamar o próximo).
final class PermissionFailure extends Failure {
  const PermissionFailure();
}

/// Recurso inexistente (ex.: barbearia não encontrada).
final class NotFoundFailure extends Failure {
  const NotFoundFailure();
}

/// Qualquer outra coisa. A causa fica disponível para logs, nunca para a UI.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([this.cause]);

  final Object? cause;

  @override
  String toString() => 'UnexpectedFailure($cause)';
}
