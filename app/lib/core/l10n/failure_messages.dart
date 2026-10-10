import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

/// Mensagens amigáveis para cada [Failure]. Um único lugar para a UI inteira.
extension FailureMessages on AppLocalizations {
  String failureMessage(Failure failure) => switch (failure) {
    QueueRuleFailure(:final code) => queueErrorMessage(code),
    NetworkFailure() => networkError,
    PermissionFailure() || UnauthenticatedFailure() => errorPermission,
    NotFoundFailure() => shopNotFound,
    UnexpectedFailure() => genericError,
  };

  String queueErrorMessage(QueueErrorCode code) => switch (code) {
    QueueErrorCode.entriesClosed => errorEntriesClosed,
    QueueErrorCode.closedToday => errorClosedToday,
    QueueErrorCode.notOpenYet => errorNotOpenYet,
    QueueErrorCode.closingSoon => errorClosingSoon,
    QueueErrorCode.queueFull => errorQueueFull,
    QueueErrorCode.alreadyInQueue => errorAlreadyInQueue,
    QueueErrorCode.invalidName => errorInvalidName,
    QueueErrorCode.rateLimited => errorRateLimited,
    QueueErrorCode.undoExpired => errorUndoExpired,
    QueueErrorCode.undoConflict => errorUndoConflict,
    QueueErrorCode.barberNotOnShift => errorBarberNotOnShift,
    QueueErrorCode.barberNotAvailable => errorBarberNotAvailable,
    QueueErrorCode.finishCurrentFirst => errorFinishCurrentFirst,
    QueueErrorCode.notTicketOwner => errorPermission,
    QueueErrorCode.invalidArgument ||
    QueueErrorCode.invalidService ||
    QueueErrorCode.invalidSchedule ||
    QueueErrorCode.ticketNotFound ||
    QueueErrorCode.invalidTicketState ||
    QueueErrorCode.barberNotFound ||
    QueueErrorCode.nothingToFinish ||
    QueueErrorCode.nothingToUndo ||
    QueueErrorCode.requestConflict ||
    QueueErrorCode.dayMismatch => genericError,
  };
}
