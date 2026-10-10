import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/queue/data/queue_functions_api.dart';
import 'package:proximo/features/queue/data/queue_mappers.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_repositories.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

/// Leituras em tempo real pelo Firestore (somente leitura — ADR 0004) e comandos pelas callables.
final class CustomerQueueRepositoryImpl implements CustomerQueueRepository {
  const CustomerQueueRepositoryImpl({required DocumentWatcher watch, required QueueFunctionsApi api})
    : _watch = watch,
      _api = api;

  final DocumentWatcher _watch;
  final QueueFunctionsApi _api;

  @override
  Stream<PublicQueue?> watchPublicQueue(String shopId) =>
      _watch('publicQueues/$shopId').map((json) => json == null ? null : QueueMappers.publicQueue(json));

  @override
  Stream<ActiveTicket?> watchActiveTicket(String uid) =>
      _watch('activeTickets/$uid').map((json) => json == null ? null : QueueMappers.activeTicket(json));

  @override
  Future<Result<JoinedTicket>> joinQueue({
    required String shopId,
    required String name,
    required String serviceId,
    TicketSource source = TicketSource.link,
    String? preferredBarberId,
  }) => _api.joinQueue(
    shopId: shopId,
    name: name,
    serviceId: serviceId,
    source: source,
    preferredBarberId: preferredBarberId,
  );

  @override
  Future<Result<void>> leaveQueue({required String shopId, required String ticketId}) =>
      _api.leaveQueue(shopId: shopId, ticketId: ticketId);
}

final class BarberQueueRepositoryImpl implements BarberQueueRepository {
  const BarberQueueRepositoryImpl(this._api);

  final QueueFunctionsApi _api;

  @override
  Future<Result<AdvanceResult>> callNext({required String shopId, FinishOutcome outcome = FinishOutcome.done}) =>
      _api.callNext(shopId: shopId, outcome: outcome);

  @override
  Future<Result<AdvanceResult>> finishCurrent({
    required String shopId,
    FinishOutcome outcome = FinishOutcome.done,
  }) => _api.finishCurrent(shopId: shopId, outcome: outcome);

  @override
  Future<Result<void>> undoLast({required String shopId}) => _api.undoLast(shopId: shopId);

  @override
  Future<Result<void>> removeTicket({required String shopId, required String ticketId}) =>
      _api.removeTicket(shopId: shopId, ticketId: ticketId);

  @override
  Future<Result<void>> setBarberStatus({required String shopId, required BarberStatus status}) =>
      _api.setBarberStatus(shopId: shopId, status: status);

  @override
  Future<Result<void>> setAcceptingEntries({required String shopId, required bool accepting}) =>
      _api.setAcceptingEntries(shopId: shopId, accepting: accepting);
}
