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
  ///
  /// [servingTicketId] é quem a tela mostra na cadeira do barbeiro (`null` = ninguém). Se o
  /// servidor discordar, a tela está desatualizada e o comando é recusado (`serving-changed`)
  /// em vez de finalizar outra pessoa.
  ///
  /// [requestId] repete um pedido que ficou sem resposta: se o servidor já o tinha aplicado,
  /// devolve o mesmo resultado em vez de avançar a fila de novo. Sem ele, o pedido é novo.
  Future<Result<AdvanceResult>> callNext({
    required String shopId,
    required String? servingTicketId,
    FinishOutcome outcome = FinishOutcome.done,
    String? requestId,
  });

  /// Finaliza o atual com [outcome] sem chamar ninguém. [servingTicketId] e [requestId] como em
  /// [callNext].
  Future<Result<AdvanceResult>> finishCurrent({
    required String shopId,
    required String? servingTicketId,
    FinishOutcome outcome = FinishOutcome.done,
    String? requestId,
  });

  Future<Result<void>> undoLast({required String shopId});

  Future<Result<void>> removeTicket({required String shopId, required String ticketId});

  Future<Result<void>> setBarberStatus({required String shopId, required BarberStatus status});

  Future<Result<void>> setAcceptingEntries({required String shopId, required bool accepting});
}
