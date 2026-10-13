import { HttpsError, onCall, type CallableRequest } from 'firebase-functions/v2/https';

import {
  callNext as callNextCommand,
  finishCurrent as finishCurrentCommand,
  joinQueue as joinQueueCommand,
  JOIN_RATE_LIMIT,
  leaveQueue as leaveQueueCommand,
  parseAcceptingEntriesInput,
  parseAdvanceInput,
  parseBarberStatusInput,
  parseJoinQueueInput,
  parseShopActionInput,
  parseTicketInput,
  removeTicket as removeTicketCommand,
  setAcceptingEntries as setAcceptingEntriesCommand,
  setBarberStatus as setBarberStatusCommand,
  undoLast as undoLastCommand,
} from '../domain';
import { APP_CHECK_ENFORCED, REGION } from './app';
import { toHttpsError } from './errors';
import { runQueueCommand, type Member } from './queueRepository';
import { refs } from './refs';

// Opções explícitas por função (em vez de setGlobalOptions) para não depender da ordem de carregamento dos módulos.
const callableOptions = { region: REGION, maxInstances: 10, enforceAppCheck: APP_CHECK_ENFORCED, cors: true } as const;

/** Envolve o handler: exige login (anônimo vale) e padroniza erros. */
function callable<R>(name: string, handler: (request: CallableRequest, uid: string) => Promise<R>) {
  return onCall(callableOptions, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Faça login para continuar.');
    try {
      return await handler(request, uid);
    } catch (error) {
      throw toHttpsError(error, { fn: name });
    }
  });
}

function requireMember(member: Member | null): Member {
  // runQueueCommand já recusa não-membros quando requireMember=true; isto apenas estreita o tipo.
  if (!member) throw new HttpsError('permission-denied', 'Acesso restrito à equipe.');
  return member;
}

// ---------------------------------------------------------------------------
// Cliente
// ---------------------------------------------------------------------------

export const joinQueue = callable('joinQueue', (request, uid) => {
  const input = parseJoinQueueInput(request.data);
  const newTicketId = refs.newId();
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: false,
    loadActiveTicket: true,
    rateLimit: { key: 'join', policy: JOIN_RATE_LIMIT },
    execute: ({ day, ctx, activeTicket }) =>
      joinQueueCommand(day, ctx, {
        requestId: input.requestId,
        actorUid: uid,
        newTicketId,
        name: input.name,
        serviceId: input.serviceId,
        source: input.source,
        preferredBarberId: input.preferredBarberId,
        activeTicket,
      }),
  });
});

export const leaveQueue = callable('leaveQueue', (request, uid) => {
  const input = parseTicketInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: false,
    execute: ({ day, ctx }) =>
      leaveQueueCommand(day, ctx, { requestId: input.requestId, actorUid: uid, ticketId: input.ticketId }),
  });
});

// ---------------------------------------------------------------------------
// Equipe (barbeiro age sempre em nome próprio: barberId = uid autenticado)
// ---------------------------------------------------------------------------

export const callNext = callable('callNext', (request, uid) => {
  const input = parseAdvanceInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,
    execute: ({ day, ctx }) =>
      callNextCommand(day, ctx, {
        requestId: input.requestId,
        actorUid: uid,
        barberId: uid,
        outcome: input.outcome,
        expectedServingTicketId: input.expectedServingTicketId,
      }),
  });
});

export const finishCurrent = callable('finishCurrent', (request, uid) => {
  const input = parseAdvanceInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,
    execute: ({ day, ctx }) =>
      finishCurrentCommand(day, ctx, {
        requestId: input.requestId,
        actorUid: uid,
        barberId: uid,
        outcome: input.outcome,
        expectedServingTicketId: input.expectedServingTicketId,
      }),
  });
});

export const undoLast = callable('undoLast', (request, uid) => {
  const input = parseShopActionInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,
    execute: ({ day, ctx }) => undoLastCommand(day, ctx, { requestId: input.requestId, actorUid: uid, barberId: uid }),
  });
});

export const removeTicket = callable('removeTicket', (request, uid) => {
  const input = parseTicketInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,
    execute: ({ day, ctx }) =>
      removeTicketCommand(day, ctx, { requestId: input.requestId, actorUid: uid, barberId: uid, ticketId: input.ticketId }),
  });
});

export const setBarberStatus = callable('setBarberStatus', (request, uid) => {
  const input = parseBarberStatusInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,
    execute: ({ day, ctx, member }) =>
      setBarberStatusCommand(day, ctx, {
        requestId: input.requestId,
        actorUid: uid,
        barberId: uid,
        displayName: requireMember(member).displayName,
        status: input.status,
      }),
  });
});

export const setAcceptingEntries = callable('setAcceptingEntries', (request, uid) => {
  const input = parseAcceptingEntriesInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,
    execute: ({ day, ctx }) =>
      setAcceptingEntriesCommand(day, ctx, { requestId: input.requestId, actorUid: uid, accepting: input.accepting }),
  });
});
