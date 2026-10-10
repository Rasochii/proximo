import { sanitizeDisplayName } from './displayName';
import { DomainError } from './errors';
import {
  evaluateEntry,
  findTicket,
  isActive,
  isBlockingActiveTicket,
  replaceTickets,
  requireBarberOnShift,
  waitingTickets,
  type DayContext,
} from './queueDay';
import { recordDuration, removeSample } from './stats';
import type {
  ActiveTicketRef,
  BarberDayState,
  BarberStatus,
  CommandName,
  Effect,
  FinishOutcome,
  QueueDay,
  ServiceStats,
  Ticket,
  TicketSource,
  UndoEntry,
  UndoableCommand,
} from './types';

/** Quantos `requestId` ficam guardados para idempotência. */
export const PROCESSED_HISTORY_LIMIT = 100;
/** Folga para latência de rede ao desfazer. */
export const UNDO_GRACE_MS = 5_000;

export interface CommandOutcome<R> {
  readonly day: QueueDay;
  readonly stats: ServiceStats;
  readonly result: R;
  readonly effects: readonly Effect[];
  /** true quando o `requestId` já tinha sido processado: nada deve ser gravado. */
  readonly replayed: boolean;
}

interface Mutation<R> {
  readonly day: QueueDay;
  readonly stats?: ServiceStats;
  readonly result: R;
  readonly effects?: readonly Effect[];
}

interface CommandMeta {
  readonly requestId: string;
  readonly actorUid: string;
}

/**
 * Executa um comando com idempotência: se o `requestId` já foi processado pelo mesmo ator,
 * devolve o resultado anterior sem alterar nada (retries de rede ficam seguros).
 */
function execute<R>(
  command: CommandName,
  day: QueueDay,
  ctx: DayContext,
  meta: CommandMeta,
  run: () => Mutation<R>,
): CommandOutcome<R> {
  const previous = day.processed.find((p) => p.requestId === meta.requestId);
  if (previous) {
    if (previous.actorUid !== meta.actorUid || previous.command !== command) {
      throw new DomainError('request-conflict');
    }
    return { day, stats: ctx.stats, result: previous.result as R, effects: [], replayed: true };
  }

  const mutation = run();
  const processed = [
    ...mutation.day.processed,
    { requestId: meta.requestId, actorUid: meta.actorUid, command, at: ctx.nowMs, result: mutation.result },
  ].slice(-PROCESSED_HISTORY_LIMIT);

  return {
    day: { ...mutation.day, processed, version: day.version + 1, updatedAt: ctx.nowMs },
    stats: mutation.stats ?? ctx.stats,
    result: mutation.result,
    effects: mutation.effects ?? [],
    replayed: false,
  };
}

// ---------------------------------------------------------------------------
// Cliente
// ---------------------------------------------------------------------------

export interface JoinQueueCommand extends CommandMeta {
  /** Id gerado pela infraestrutura para o novo ticket. */
  readonly newTicketId: string;
  readonly name: unknown;
  readonly serviceId: string;
  readonly source: TicketSource;
  readonly preferredBarberId: string | null;
  /** Ticket ativo atual do usuário (de `activeTickets/{uid}`), se houver. */
  readonly activeTicket: ActiveTicketRef | null;
}

export interface JoinQueueResult {
  readonly ticketId: string;
  readonly number: number;
}

export function joinQueue(day: QueueDay, ctx: DayContext, cmd: JoinQueueCommand): CommandOutcome<JoinQueueResult> {
  return execute('joinQueue', day, ctx, cmd, () => {
    const { displayName, label } = sanitizeDisplayName(cmd.name);

    const service = ctx.shop.services.find((s) => s.id === cmd.serviceId && s.active);
    if (!service) throw new DomainError('invalid-service');

    if (cmd.preferredBarberId !== null) {
      const barber = day.barbers[cmd.preferredBarberId];
      if (!barber || barber.status === 'off') throw new DomainError('barber-not-found');
    }

    const alreadyHere = day.tickets.some((t) => t.customerUid === cmd.actorUid && isActive(t));
    if (alreadyHere || isBlockingActiveTicket(cmd.activeTicket, day)) {
      throw new DomainError('already-in-queue');
    }

    const entry = evaluateEntry(day, ctx, { serviceId: service.id, preferredBarberId: cmd.preferredBarberId });
    if (!entry.open) throw new DomainError(entry.reason ?? 'entries-closed');

    const ticket: Ticket = {
      id: cmd.newTicketId,
      number: day.nextNumber,
      displayName,
      label,
      customerUid: cmd.actorUid,
      serviceId: service.id,
      preferredBarberId: cmd.preferredBarberId,
      status: 'waiting',
      source: cmd.source,
      createdAt: ctx.nowMs,
      calledAt: null,
      finishedAt: null,
      calledBy: null,
    };

    return {
      day: { ...day, tickets: [...day.tickets, ticket], nextNumber: day.nextNumber + 1 },
      result: { ticketId: ticket.id, number: ticket.number },
      effects: [
        {
          type: 'activeTicket.set',
          uid: cmd.actorUid,
          ref: { shopId: day.shopId, dateKey: day.dateKey, ticketId: ticket.id, number: ticket.number },
          onlyIfAbsent: false,
        },
      ],
    };
  });
}

export interface LeaveQueueCommand extends CommandMeta {
  readonly ticketId: string;
}

export interface TicketResult {
  readonly ticketId: string;
}

export function leaveQueue(day: QueueDay, ctx: DayContext, cmd: LeaveQueueCommand): CommandOutcome<TicketResult> {
  return execute('leaveQueue', day, ctx, cmd, () => {
    const ticket = findTicket(day, cmd.ticketId);
    if (!ticket) throw new DomainError('ticket-not-found');
    if (ticket.customerUid !== cmd.actorUid) throw new DomainError('not-ticket-owner');
    if (!isActive(ticket)) throw new DomainError('invalid-ticket-state');

    const cancelled: Ticket = { ...ticket, status: 'cancelled', finishedAt: ctx.nowMs };
    return {
      day: {
        ...day,
        tickets: replaceTickets(day.tickets, [cancelled]),
        barbers: releaseBarberOf(day.barbers, ticket.id),
      },
      result: { ticketId: ticket.id },
      effects: [{ type: 'activeTicket.clear', uid: ticket.customerUid, ticketId: ticket.id }],
    };
  });
}

// ---------------------------------------------------------------------------
// Barbeiro
// ---------------------------------------------------------------------------

export interface BarberCommand extends CommandMeta {
  /** Barbeiro que executa a ação (já autorizado pela infraestrutura). */
  readonly barberId: string;
}

export interface CallNextCommand extends BarberCommand {
  /** Como terminou o atendimento atual, se houver. */
  readonly outcome: FinishOutcome;
}

export interface CalledTicket {
  readonly ticketId: string;
  readonly number: number;
  readonly label: string;
}

export interface CallNextResult {
  readonly finished: { readonly ticketId: string; readonly outcome: FinishOutcome } | null;
  readonly called: CalledTicket | null;
}

/**
 * O botão "Próximo!": finaliza o atendimento atual (atendido ou "não veio") e chama o
 * primeiro ticket compatível — tudo numa única operação atômica e desfazível.
 */
export function callNext(day: QueueDay, ctx: DayContext, cmd: CallNextCommand): CommandOutcome<CallNextResult> {
  return execute('callNext', day, ctx, cmd, () => advance(day, ctx, cmd, cmd.outcome, true, 'callNext'));
}

export interface FinishCurrentCommand extends BarberCommand {
  readonly outcome: FinishOutcome;
}

/** Finaliza o atendimento atual sem chamar o próximo (ex.: antes do almoço). */
export function finishCurrent(
  day: QueueDay,
  ctx: DayContext,
  cmd: FinishCurrentCommand,
): CommandOutcome<CallNextResult> {
  return execute('finishCurrent', day, ctx, cmd, () => {
    const barber = requireBarberOnShift(day, cmd.barberId);
    if (!barber.currentTicketId) throw new DomainError('nothing-to-finish');
    return advance(day, ctx, cmd, cmd.outcome, false, 'finishCurrent');
  });
}

function advance(
  day: QueueDay,
  ctx: DayContext,
  cmd: BarberCommand,
  outcome: FinishOutcome,
  callAnother: boolean,
  command: UndoableCommand,
): Mutation<CallNextResult> {
  const barber = requireBarberOnShift(day, cmd.barberId);
  if (callAnother && barber.status !== 'available') throw new DomainError('barber-not-available');

  const before: Ticket[] = [];
  const after: Ticket[] = [];
  const effects: Effect[] = [];
  let stats = ctx.stats;
  let finished: CallNextResult['finished'] = null;

  const current = barber.currentTicketId ? findTicket(day, barber.currentTicketId) : undefined;
  if (current && current.status === 'called') {
    const done: Ticket = { ...current, status: outcome, finishedAt: ctx.nowMs };
    before.push(current);
    after.push(done);
    effects.push({ type: 'activeTicket.clear', uid: current.customerUid, ticketId: current.id });
    finished = { ticketId: current.id, outcome };

    const service = ctx.shop.services.find((s) => s.id === current.serviceId);
    if (outcome === 'done' && service && current.calledAt !== null) {
      stats = recordDuration(stats, service, { ticketId: current.id, minutes: (ctx.nowMs - current.calledAt) / 60_000 });
    }
  }

  let called: CalledTicket | null = null;
  if (callAnother) {
    const next = waitingTickets(day).find((t) => t.preferredBarberId === null || t.preferredBarberId === barber.id);
    if (next) {
      before.push(next);
      after.push({ ...next, status: 'called', calledAt: ctx.nowMs, calledBy: barber.id });
      called = { ticketId: next.id, number: next.number, label: next.label };
    }
  }

  if (!finished && !called) {
    // Nada a fazer (fila vazia e ninguém em atendimento): não cria entrada de desfazer.
    return { day, result: { finished: null, called: null } };
  }

  const updatedBarber: BarberDayState = { ...barber, currentTicketId: called?.ticketId ?? null };
  const undoEntry: UndoEntry = {
    requestId: cmd.requestId,
    command,
    at: ctx.nowMs,
    before: { tickets: before, barber },
    after: { tickets: after, barber: updatedBarber },
  };

  return {
    day: {
      ...day,
      tickets: replaceTickets(day.tickets, after),
      barbers: { ...day.barbers, [barber.id]: updatedBarber },
      undo: { ...day.undo, [barber.id]: undoEntry },
    },
    stats,
    result: { finished, called },
    effects,
  };
}

export interface UndoLastResult {
  readonly undone: UndoableCommand;
  readonly restoredTicketIds: readonly string[];
}

/**
 * Desfaz o último "Próximo!"/"Finalizar" do barbeiro, dentro da janela configurada,
 * desde que nada tenha mudado nesses tickets nesse meio-tempo.
 */
export function undoLast(day: QueueDay, ctx: DayContext, cmd: BarberCommand): CommandOutcome<UndoLastResult> {
  return execute('undoLast', day, ctx, cmd, () => {
    const entry = day.undo[cmd.barberId];
    if (!entry) throw new DomainError('nothing-to-undo');
    if (ctx.nowMs - entry.at > ctx.shop.settings.undoWindowSec * 1000 + UNDO_GRACE_MS) {
      throw new DomainError('undo-expired');
    }

    const barber = day.barbers[cmd.barberId];
    const unchanged =
      barber !== undefined &&
      barber.status === entry.after.barber.status &&
      barber.currentTicketId === entry.after.barber.currentTicketId &&
      entry.after.tickets.every((expected) => {
        const actual = findTicket(day, expected.id);
        return actual !== undefined && actual.status === expected.status && actual.calledBy === expected.calledBy;
      });
    if (!unchanged) throw new DomainError('undo-conflict');

    let stats = ctx.stats;
    const effects: Effect[] = [];
    for (const original of entry.before.tickets) {
      const changed = entry.after.tickets.find((t) => t.id === original.id);
      if (original.status === 'called' && changed && changed.status !== 'called') {
        // Atendimento finalizado volta a estar em andamento: desfaz estatística e restaura o ticket ativo.
        stats = removeSample(stats, original.serviceId, original.id);
        effects.push({
          type: 'activeTicket.set',
          uid: original.customerUid,
          ref: { shopId: day.shopId, dateKey: day.dateKey, ticketId: original.id, number: original.number },
          onlyIfAbsent: true,
        });
      }
    }

    const { [cmd.barberId]: _removed, ...remainingUndo } = day.undo;
    return {
      day: {
        ...day,
        tickets: replaceTickets(day.tickets, entry.before.tickets),
        barbers: { ...day.barbers, [cmd.barberId]: entry.before.barber },
        undo: remainingUndo,
      },
      stats,
      result: { undone: entry.command, restoredTicketIds: entry.before.tickets.map((t) => t.id) },
      effects,
    };
  });
}

export interface RemoveTicketCommand extends BarberCommand {
  readonly ticketId: string;
}

/** Barbeiro remove um ticket aguardando (ex.: nome ofensivo, entrada falsa). */
export function removeTicket(day: QueueDay, ctx: DayContext, cmd: RemoveTicketCommand): CommandOutcome<TicketResult> {
  return execute('removeTicket', day, ctx, cmd, () => {
    requireBarberOnShift(day, cmd.barberId);
    const ticket = findTicket(day, cmd.ticketId);
    if (!ticket) throw new DomainError('ticket-not-found');
    if (ticket.status !== 'waiting') throw new DomainError('invalid-ticket-state');

    const removed: Ticket = { ...ticket, status: 'removed', finishedAt: ctx.nowMs };
    return {
      day: { ...day, tickets: replaceTickets(day.tickets, [removed]) },
      result: { ticketId: ticket.id },
      effects: [{ type: 'activeTicket.clear', uid: ticket.customerUid, ticketId: ticket.id }],
    };
  });
}

export interface SetBarberStatusCommand extends BarberCommand {
  readonly displayName: string;
  readonly status: BarberStatus;
}

export interface BarberStatusResult {
  readonly barberId: string;
  readonly status: BarberStatus;
}

/** Iniciar expediente (`available`), pausar (`paused`) ou encerrar (`off`). */
export function setBarberStatus(
  day: QueueDay,
  ctx: DayContext,
  cmd: SetBarberStatusCommand,
): CommandOutcome<BarberStatusResult> {
  return execute('setBarberStatus', day, ctx, cmd, () => {
    const existing = day.barbers[cmd.barberId];
    if (cmd.status === 'off' && existing?.currentTicketId) throw new DomainError('finish-current-first');

    const barber: BarberDayState = {
      id: cmd.barberId,
      displayName: cmd.displayName,
      status: cmd.status,
      currentTicketId: existing?.currentTicketId ?? null,
      statusSince: existing?.status === cmd.status ? existing.statusSince : ctx.nowMs,
    };
    return {
      day: { ...day, barbers: { ...day.barbers, [cmd.barberId]: barber } },
      result: { barberId: cmd.barberId, status: cmd.status },
    };
  });
}

export interface SetAcceptingEntriesCommand extends CommandMeta {
  readonly accepting: boolean;
}

/** "Fechar entrada" / "Reabrir entrada" — quem já está na fila continua sendo atendido. */
export function setAcceptingEntries(
  day: QueueDay,
  ctx: DayContext,
  cmd: SetAcceptingEntriesCommand,
): CommandOutcome<{ readonly accepting: boolean }> {
  return execute('setAcceptingEntries', day, ctx, cmd, () => ({
    day: { ...day, acceptingEntries: cmd.accepting },
    result: { accepting: cmd.accepting },
  }));
}

function releaseBarberOf(
  barbers: Readonly<Record<string, BarberDayState>>,
  ticketId: string,
): Readonly<Record<string, BarberDayState>> {
  const entry = Object.values(barbers).find((b) => b.currentTicketId === ticketId);
  return entry ? { ...barbers, [entry.id]: { ...entry, currentTicketId: null } } : barbers;
}
