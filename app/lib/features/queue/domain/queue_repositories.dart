import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

/// Jornada do cliente: acompanhar a fila, entrar e sair.
abstract interface class CustomerQueueRepository {
  /// Projeção pública em tempo real; `null` enquanto a barbearia nunca abriu a fila.
  Stream<PublicQueue?> watchPublicQueue(String shopId);

  /// Ticket ativo do usuário logado (`null` se não estiver em nenhuma fila).
  Stream<ActiveTicket?> watchActiveTicket(String uid);

  Future<Result<JoinedTicket>> joinQueue({
    required String shopId,
    required String name,
    required String serviceId,
    TicketSource source = TicketSource.link,
    String? preferredBarberId,
  });

  Future<Result<void>> leaveQueue({required String shopId, required String ticketId});
}

/// Jornada do barbeiro: comandos do console. O barbeiro sempre age em nome próprio
/// (o backend usa o uid autenticado como `barberId`).
abstract interface class BarberQueueRepository {
  /// "Próximo!": finaliza o atual com [outcome] e chama o próximo compatível.
  Future<Result<AdvanceResult>> callNext({
    required String shopId,
    FinishOutcome outcome = FinishOutcome.done,
  });

  Future<Result<AdvanceResult>> finishCurrent({
    required String shopId,
    FinishOutcome outcome = FinishOutcome.done,
  });

  Future<Result<void>> undoLast({required String shopId});

  Future<Result<void>> removeTicket({required String shopId, required String ticketId});

  Future<Result<void>> setBarberStatus({required String shopId, required BarberStatus status});

  Future<Result<void>> setAcceptingEntries({required String shopId, required bool accepting});
}
