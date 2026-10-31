import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/ids/request_id.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/queue/data/queue_mappers.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

/// Política de novas tentativas para falhas transitórias de rede.
final class RetryPolicy {
  const RetryPolicy({this.maxAttempts = 3, this.baseDelay = const Duration(milliseconds: 400)});

  final int maxAttempts;
  final Duration baseDelay;

  /// Espera exponencial: 400 ms, 800 ms, 1,6 s…
  Duration delayFor(int attempt) => baseDelay * (1 << (attempt - 1));
}

typedef Sleep = Future<void> Function(Duration duration);

/// Cliente das callables da fila.
///
/// - Cada comando ganha um `requestId` (UUID v4) **reutilizado em todas as tentativas**:
///   se a resposta se perder no caminho, o retry devolve o mesmo resultado em vez de duplicar a ação.
/// - Erros viram [Failure]s tipadas; o código de negócio vem de `details.code`.
final class QueueFunctionsApi {
  QueueFunctionsApi({
    required CallableInvoker invoke,
    required RequestIdGenerator newRequestId,
    RetryPolicy retryPolicy = const RetryPolicy(),
    Sleep sleep = Future<void>.delayed,
  }) : _invoke = invoke,
       _newRequestId = newRequestId,
       _retry = retryPolicy,
       _sleep = sleep;

  final CallableInvoker _invoke;
  final RequestIdGenerator _newRequestId;
  final RetryPolicy _retry;
  final Sleep _sleep;

  Future<Result<JoinedTicket>> joinQueue({
    required String shopId,
    required String name,
    required String serviceId,
    required TicketSource source,
    String? preferredBarberId,
  }) => _command(
    'joinQueue',
    {
      'shopId': shopId,
      'name': name,
      'serviceId': serviceId,
      'source': source.wire,
      'preferredBarberId': ?preferredBarberId,
    },
    QueueMappers.joinedTicket,
  );

  Future<Result<void>> leaveQueue({required String shopId, required String ticketId}) =>
      _command('leaveQueue', {'shopId': shopId, 'ticketId': ticketId}, _ignore);

  /// [servingTicketId] é quem o console mostra na cadeira (`null` = ninguém). Vai sempre no
  /// pedido, mesmo nulo: o servidor recusa o avanço se a cadeira estiver diferente.
  /// [requestId] repete um pedido anterior que ficou sem resposta; sem ele, o pedido é novo.
  Future<Result<AdvanceResult>> callNext({
    required String shopId,
    required FinishOutcome outcome,
    required String? servingTicketId,
    String? requestId,
  }) => _command(
    'callNext',
    {
      'shopId': shopId,
      'outcome': outcome.wire,
      'expectedServingTicketId': servingTicketId,
    },
    QueueMappers.advanceResult,
    requestId: requestId,
  );

  Future<Result<AdvanceResult>> finishCurrent({
    required String shopId,
    required FinishOutcome outcome,
    required String? servingTicketId,
    String? requestId,
  }) => _command(
    'finishCurrent',
    {
      'shopId': shopId,
      'outcome': outcome.wire,
      'expectedServingTicketId': servingTicketId,
    },
    QueueMappers.advanceResult,
    requestId: requestId,
  );

  Future<Result<void>> undoLast({required String shopId}) =>
      _command('undoLast', {'shopId': shopId}, _ignore);

  Future<Result<void>> removeTicket({required String shopId, required String ticketId}) =>
      _command('removeTicket', {'shopId': shopId, 'ticketId': ticketId}, _ignore);

  Future<Result<void>> setBarberStatus({required String shopId, required BarberStatus status}) =>
      _command('setBarberStatus', {'shopId': shopId, 'status': status.wire}, _ignore);

  Future<Result<void>> setAcceptingEntries({required String shopId, required bool accepting}) =>
      _command('setAcceptingEntries', {'shopId': shopId, 'accepting': accepting}, _ignore);

  static void _ignore(JsonMap _) {}

  Future<Result<T>> _command<T>(
    String name,
    JsonMap payload,
    T Function(JsonMap json) parse, {
    String? requestId,
  }) async {
    final request = {'requestId': requestId ?? _newRequestId(), ...payload};

    for (var attempt = 1; ; attempt++) {
      try {
        final data = await _invoke(name, request);
        return Ok(parse(data == null ? const <String, Object?>{} : asJsonMap(data, name)));
      } on CallableException catch (error) {
        final failure = _toFailure(error);
        final canRetry = failure is NetworkFailure && attempt < _retry.maxAttempts;
        if (!canRetry) return Err(failure);
        await _sleep(_retry.delayFor(attempt));
      } on FormatException catch (error) {
        return Err(UnexpectedFailure(error));
      } on Exception catch (error) {
        // É nesta camada que exceção vira Failure: quem chama nunca fica esperando para sempre.
        return Err(UnexpectedFailure(error));
      }
    }
  }

  static Failure _toFailure(CallableException error) {
    final details = error.details;
    final domainCode = details is Map<String, Object?> ? details['code'] : null;
    final code = QueueErrorCode.fromWire(domainCode is String ? domainCode : null);
    if (code != null) {
      final retryAfterMs = details is Map<String, Object?> ? details['retryAfterMs'] : null;
      return QueueRuleFailure(
        code,
        retryAfter: retryAfterMs is num ? Duration(milliseconds: retryAfterMs.toInt()) : null,
      );
    }
    return switch (error.code) {
      // Falhas transitórias: vale tentar de novo com o mesmo requestId.
      'unavailable' || 'deadline-exceeded' => const NetworkFailure(),
      'unauthenticated' => const UnauthenticatedFailure(),
      'permission-denied' => const PermissionFailure(),
      'not-found' => const NotFoundFailure(),
      _ => UnexpectedFailure(error),
    };
  }
}
