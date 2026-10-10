import 'package:meta/meta.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/features/queue/domain/eta.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

/// Projeção pública da fila (`publicQueues/{shopId}`): o que o cliente, o link web e a TV enxergam.
/// Não contém dados pessoais — apenas rótulos como "Lucas M.".
@immutable
final class PublicQueue {
  const PublicQueue({
    required this.shopId,
    required this.shopName,
    required this.dateKey,
    required this.entry,
    required this.barbers,
    required this.nowServing,
    required this.waiting,
    required this.version,
    required this.updatedAt,
  });

  final String shopId;
  final String shopName;
  final String dateKey;
  final EntryState entry;
  final List<BarberOnDuty> barbers;
  final List<ServingTicket> nowServing;
  final List<WaitingTicket> waiting;
  final int version;
  final DateTime updatedAt;

  int get waitingCount => waiting.length;

  /// Ticket do usuário na fila de espera, se estiver aguardando.
  WaitingTicket? waitingTicket(String ticketId) {
    for (final ticket in waiting) {
      if (ticket.ticketId == ticketId) return ticket;
    }
    return null;
  }

  /// Se o ticket está sendo atendido agora.
  ServingTicket? servingTicket(String ticketId) {
    for (final ticket in nowServing) {
      if (ticket.ticketId == ticketId) return ticket;
    }
    return null;
  }
}

/// Se dá para entrar agora e com qual espera estimada.
@immutable
final class EntryState {
  const EntryState({required this.open, required this.eta, this.closedReason});

  final bool open;
  final QueueErrorCode? closedReason;
  final Eta eta;
}

@immutable
final class BarberOnDuty {
  const BarberOnDuty({
    required this.id,
    required this.displayName,
    required this.status,
    this.servingNumber,
  });

  final String id;
  final String displayName;
  final BarberStatus status;
  final int? servingNumber;
}

@immutable
final class ServingTicket {
  const ServingTicket({
    required this.ticketId,
    required this.number,
    required this.label,
    this.barberId,
  });

  final String ticketId;
  final int number;
  final String label;
  final String? barberId;
}

@immutable
final class WaitingTicket {
  const WaitingTicket({
    required this.ticketId,
    required this.number,
    required this.label,
    required this.serviceId,
    required this.position,
    required this.eta,
    this.preferredBarberId,
  });

  final String ticketId;
  final int number;
  final String label;
  final String serviceId;
  final String? preferredBarberId;

  /// 1 = próximo a ser chamado.
  final int position;
  final Eta eta;
}
