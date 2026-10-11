import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/queue/domain/eta.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

/// Converte os documentos do backend (formato em `functions/src/domain/projection.ts`) para o domínio.
abstract final class QueueMappers {
  static PublicQueue publicQueue(JsonMap json) {
    final entry = json.readMap('entry');
    final validUntil = json.readIntOrNull('validUntil');
    return PublicQueue(
      shopId: json.readString('shopId'),
      shopName: json.readString('shopName'),
      dateKey: json.readString('dateKey'),
      entry: EntryState(
        open: entry.readBool('open'),
        closedReason: QueueErrorCode.fromWire(entry.readStringOrNull('reason')),
        eta: eta(entry.readMap('eta')),
      ),
      barbers: json.readList('barbers', _barber),
      nowServing: json.readList('nowServing', _serving),
      waiting: json.readList('waiting', _waiting),
      version: json.readInt('version'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json.readInt('updatedAt')),
      validUntil: validUntil == null ? null : DateTime.fromMillisecondsSinceEpoch(validUntil),
    );
  }

  static Eta eta(JsonMap json) => switch (json.readString('kind')) {
    'estimated' => EstimatedEta(Duration(minutes: json.readInt('startsInMin'))),
    'beyond_closing' => const BeyondClosingEta(),
    _ => const UnknownEta(),
  };

  static ActiveTicket activeTicket(JsonMap json) => ActiveTicket(
    shopId: json.readString('shopId'),
    dateKey: json.readString('dateKey'),
    ticketId: json.readString('ticketId'),
    number: json.readInt('number'),
  );

  static JoinedTicket joinedTicket(JsonMap json) =>
      JoinedTicket(ticketId: json.readString('ticketId'), number: json.readInt('number'));

  static AdvanceResult advanceResult(JsonMap json) {
    final finished = json.readMapOrNull('finished');
    final called = json.readMapOrNull('called');
    return AdvanceResult(
      finishedTicketId: finished?.readString('ticketId'),
      finishedOutcome: switch (finished?.readString('outcome')) {
        null => null,
        'no_show' => FinishOutcome.noShow,
        _ => FinishOutcome.done,
      },
      called: called == null
          ? null
          : CalledTicket(
              ticketId: called.readString('ticketId'),
              number: called.readInt('number'),
              label: called.readString('label'),
            ),
    );
  }

  static BarberOnDuty _barber(JsonMap json) => BarberOnDuty(
    id: json.readString('id'),
    displayName: json.readString('displayName'),
    status: BarberStatus.fromWire(json.readString('status')),
    servingNumber: json.readIntOrNull('servingNumber'),
  );

  static ServingTicket _serving(JsonMap json) => ServingTicket(
    ticketId: json.readString('ticketId'),
    number: json.readInt('number'),
    label: json.readString('label'),
    barberId: json.readStringOrNull('barberId'),
  );

  static WaitingTicket _waiting(JsonMap json) => WaitingTicket(
    ticketId: json.readString('ticketId'),
    number: json.readInt('number'),
    label: json.readString('label'),
    serviceId: json.readString('serviceId'),
    preferredBarberId: json.readStringOrNull('preferredBarberId'),
    position: json.readInt('position'),
    eta: eta(json.readMap('eta')),
  );
}
