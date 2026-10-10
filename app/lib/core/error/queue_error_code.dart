/// Códigos estáveis de regra de negócio devolvidos pelo backend em `details.code`.
///
/// Contrato espelhado de `functions/src/domain/errors.ts` — ao adicionar um código lá,
/// adicione aqui e a mensagem correspondente no ARB.
enum QueueErrorCode {
  invalidArgument('invalid-argument'),
  invalidName('invalid-name'),
  invalidService('invalid-service'),
  invalidSchedule('invalid-schedule'),
  entriesClosed('entries-closed'),
  closedToday('closed-today'),
  notOpenYet('not-open-yet'),
  closingSoon('closing-soon'),
  queueFull('queue-full'),
  alreadyInQueue('already-in-queue'),
  ticketNotFound('ticket-not-found'),
  notTicketOwner('not-ticket-owner'),
  invalidTicketState('invalid-ticket-state'),
  barberNotFound('barber-not-found'),
  barberNotOnShift('barber-not-on-shift'),
  barberNotAvailable('barber-not-available'),
  finishCurrentFirst('finish-current-first'),
  nothingToFinish('nothing-to-finish'),
  nothingToUndo('nothing-to-undo'),
  undoExpired('undo-expired'),
  undoConflict('undo-conflict'),
  requestConflict('request-conflict'),
  rateLimited('rate-limited'),
  dayMismatch('day-mismatch');

  const QueueErrorCode(this.wire);

  /// Valor trafegado pelo backend.
  final String wire;

  static final Map<String, QueueErrorCode> _byWire = {for (final code in values) code.wire: code};

  /// Código correspondente, ou `null` se o backend enviar um código desconhecido (app desatualizado).
  static QueueErrorCode? fromWire(String? wire) => wire == null ? null : _byWire[wire];
}
