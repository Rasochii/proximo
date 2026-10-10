import 'package:meta/meta.dart';

/// Enums e valores compartilhados com o backend (`functions/src/domain/types.ts`).

enum TicketSource {
  link('link'),
  qr('qr'),
  app('app'),
  counter('counter');

  const TicketSource(this.wire);

  final String wire;
}

enum FinishOutcome {
  done('done'),
  noShow('no_show');

  const FinishOutcome(this.wire);

  final String wire;
}

enum BarberStatus {
  available('available'),
  paused('paused'),
  off('off');

  const BarberStatus(this.wire);

  final String wire;

  static BarberStatus fromWire(String wire) => values.firstWhere(
    (status) => status.wire == wire,
    orElse: () => throw FormatException('BarberStatus desconhecido: $wire'),
  );
}

/// Ticket ativo do usuário (`activeTickets/{uid}`): garante 1 fila por pessoa.
@immutable
final class ActiveTicket {
  const ActiveTicket({
    required this.shopId,
    required this.dateKey,
    required this.ticketId,
    required this.number,
  });

  final String shopId;
  final String dateKey;
  final String ticketId;
  final int number;

  @override
  bool operator ==(Object other) =>
      other is ActiveTicket &&
      other.shopId == shopId &&
      other.dateKey == dateKey &&
      other.ticketId == ticketId &&
      other.number == number;

  @override
  int get hashCode => Object.hash(shopId, dateKey, ticketId, number);
}

/// Resultado de `joinQueue`.
@immutable
final class JoinedTicket {
  const JoinedTicket({required this.ticketId, required this.number});

  final String ticketId;
  final int number;

  @override
  bool operator ==(Object other) =>
      other is JoinedTicket && other.ticketId == ticketId && other.number == number;

  @override
  int get hashCode => Object.hash(ticketId, number);
}

/// Cliente chamado pelo "Próximo!".
@immutable
final class CalledTicket {
  const CalledTicket({required this.ticketId, required this.number, required this.label});

  final String ticketId;
  final int number;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is CalledTicket &&
      other.ticketId == ticketId &&
      other.number == number &&
      other.label == label;

  @override
  int get hashCode => Object.hash(ticketId, number, label);
}

/// Resultado de `callNext`/`finishCurrent`.
@immutable
final class AdvanceResult {
  const AdvanceResult({this.finishedTicketId, this.finishedOutcome, this.called});

  final String? finishedTicketId;
  final FinishOutcome? finishedOutcome;
  final CalledTicket? called;

  @override
  bool operator ==(Object other) =>
      other is AdvanceResult &&
      other.finishedTicketId == finishedTicketId &&
      other.finishedOutcome == finishedOutcome &&
      other.called == called;

  @override
  int get hashCode => Object.hash(finishedTicketId, finishedOutcome, called);
}
