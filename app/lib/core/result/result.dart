import 'package:meta/meta.dart';
import 'package:proximo/core/error/failure.dart';

/// Resultado de um comando: sucesso com valor ou [Failure] esperada.
///
/// Comandos (entrar na fila, chamar o próximo…) retornam [Result] em vez de lançar exceções,
/// para que a UI trate todos os casos com `switch` exaustivo.
@immutable
sealed class Result<T> {
  const Result();

  /// Valor em caso de sucesso, ou `null`.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// Falha em caso de erro, ou `null`.
  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final value) => Ok(transform(value)),
    Err<T>(:final failure) => Err(failure),
  };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Err($failure)';
}
