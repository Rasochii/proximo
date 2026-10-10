/**
 * Ponto de entrada das Cloud Functions do Próximo!.
 * Toda mutação da fila passa por estas callables (ADR 0004).
 */
export {
  callNext,
  finishCurrent,
  joinQueue,
  leaveQueue,
  removeTicket,
  setAcceptingEntries,
  setBarberStatus,
  undoLast,
} from './firebase/callables';
