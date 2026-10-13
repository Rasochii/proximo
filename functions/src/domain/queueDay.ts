import { DomainError, type DomainErrorCode } from './errors';
import { estimateWaits, type EtaTicket, type TicketEta } from './eta';
import { dayBounds, intervalsFor } from './schedule';
import { expectedDurationMin } from './stats';
import { toLocal, type LocalDateTime } from './time';
import type {
  ActiveTicketRef,
  ActiveTicketStatus,
  BarberDayState,
  QueueDay,
  ServiceStats,
  Shop,
  Ticket,
  TicketStatus,
} from './types';

/** Contexto de leitura necessário para avaliar regras que dependem de horário e estatísticas. */
export interface DayContext {
  readonly nowMs: number;
  readonly shop: Shop;
  readonly stats: ServiceStats;
}

export function createQueueDay(shopId: string, dateKey: string, nowMs: number): QueueDay {
  return {
    shopId,
    dateKey,
    acceptingEntries: true,
    nextNumber: 1,
    tickets: [],
    barbers: {},
    undo: {},
    processed: [],
    version: 0,
    updatedAt: nowMs,
  };
}

/** Chave do dia atual no fuso da barbearia (ex.: '2026-10-10'). */
export function currentDateKey(shop: Pick<Shop, 'timezone'>, nowMs: number): string {
  return toLocal(nowMs, shop.timezone).dateKey;
}

const ACTIVE_STATUSES: ReadonlySet<TicketStatus> = new Set<ActiveTicketStatus>(['waiting', 'called']);

export function isActive(ticket: Pick<Ticket, 'status'>): boolean {
  return ACTIVE_STATUSES.has(ticket.status);
}

export function waitingTickets(day: QueueDay): Ticket[] {
  return day.tickets.filter((t) => t.status === 'waiting').sort((a, b) => a.number - b.number);
}

export function calledTickets(day: QueueDay): Ticket[] {
  return day.tickets.filter((t) => t.status === 'called').sort((a, b) => a.number - b.number);
}

export function findTicket(day: QueueDay, ticketId: string): Ticket | undefined {
  return day.tickets.find((t) => t.id === ticketId);
}

/** Duração esperada de um serviço (mediana real ou padrão). Serviço desconhecido usa 30 min. */
export function durationResolver(ctx: DayContext): (serviceId: string) => number {
  const byId = new Map(ctx.shop.services.map((s) => [s.id, s]));
  return (serviceId) => {
    const service = byId.get(serviceId);
    return service ? expectedDurationMin(ctx.stats, service) : 30;
  };
}

/** Estima a espera de todos os tickets aguardando (e, opcionalmente, de um ticket hipotético no fim). */
export function estimateDay(day: QueueDay, ctx: DayContext, phantom?: EtaTicket): Map<string, TicketEta> {
  const local = toLocal(ctx.nowMs, ctx.shop.timezone);
  const waiting: EtaTicket[] = waitingTickets(day);
  if (phantom) waiting.push(phantom);
  return estimateWaits({
    waiting,
    barbers: Object.values(day.barbers),
    inService: calledTickets(day),
    intervals: intervalsFor(ctx.shop.schedule, local.weekday),
    nowMs: ctx.nowMs,
    nowMinute: local.minuteOfDay,
    durationOf: durationResolver(ctx),
  });
}

export type EntryClosedReason = Extract<
  DomainErrorCode,
  'entries-closed' | 'closed-today' | 'not-open-yet' | 'closing-soon' | 'queue-full' | 'day-mismatch'
>;

export interface EntryState {
  readonly open: boolean;
  readonly reason: EntryClosedReason | null;
  /** Espera estimada para quem entrar agora (null se desconhecida). */
  readonly eta: TicketEta;
}

const PHANTOM_ID = '__phantom__';

/**
 * Avalia se um novo cliente pode entrar agora. Usado tanto para validar o `joinQueue`
 * quanto para mostrar no app ("Entrar agora · ~25 min") — uma única regra para os dois.
 */
export function evaluateEntry(
  day: QueueDay,
  ctx: DayContext,
  candidate: { readonly serviceId?: string; readonly preferredBarberId?: string | null } = {},
): EntryState {
  const local: LocalDateTime = toLocal(ctx.nowMs, ctx.shop.timezone);
  const closed = (reason: EntryClosedReason): EntryState => ({ open: false, reason, eta: { kind: 'unknown' } });

  if (local.dateKey !== day.dateKey) return closed('day-mismatch');
  if (!day.acceptingEntries) return closed('entries-closed');

  const bounds = dayBounds(intervalsFor(ctx.shop.schedule, local.weekday));
  if (!bounds) return closed('closed-today');
  if (local.minuteOfDay < bounds.start - ctx.shop.settings.openEntryMinutesBefore) return closed('not-open-yet');
  if (local.minuteOfDay >= bounds.end - ctx.shop.settings.closeEntryMinutesBefore) return closed('closing-soon');
  if (day.tickets.length >= ctx.shop.settings.maxTicketsPerDay) return closed('queue-full');

  const phantom: EtaTicket = {
    id: PHANTOM_ID,
    number: Number.MAX_SAFE_INTEGER,
    serviceId: candidate.serviceId ?? defaultServiceId(ctx.shop),
    preferredBarberId: candidate.preferredBarberId ?? null,
  };
  const eta = estimateDay(day, ctx, phantom).get(PHANTOM_ID) ?? { kind: 'unknown' };
  if (eta.kind === 'beyond_closing') return { open: false, reason: 'closing-soon', eta };
  return { open: true, reason: null, eta };
}

function defaultServiceId(shop: Shop): string {
  return shop.services.find((s) => s.active)?.id ?? '';
}

/**
 * Um ticket ativo registrado bloqueia nova entrada se ainda estiver valendo:
 * - mesma barbearia e mesmo dia → confere o estado real no agregado;
 * - outra barbearia → bloqueia apenas se for do mesmo dia (referências de dias anteriores são obsoletas).
 */
export function isBlockingActiveTicket(ref: ActiveTicketRef | null, day: QueueDay): boolean {
  if (!ref) return false;
  if (ref.shopId === day.shopId) {
    if (ref.dateKey !== day.dateKey) return false;
    const ticket = findTicket(day, ref.ticketId);
    return ticket !== undefined && isActive(ticket);
  }
  return ref.dateKey === day.dateKey;
}

/**
 * Quem está na cadeira do barbeiro: o ticket para o qual ele aponta, se ainda estiver em
 * atendimento. É a mesma pessoa que a projeção pública mostra para aquele barbeiro. A conferência
 * do console (`serving-changed`) depende de as duas visões nunca divergirem, então tudo que
 * pergunta "quem este barbeiro atende?" passa por aqui.
 */
export function servingTicketOf(day: QueueDay, barber: Pick<BarberDayState, 'currentTicketId'>): Ticket | undefined {
  const ticket = barber.currentTicketId ? findTicket(day, barber.currentTicketId) : undefined;
  return ticket?.status === 'called' ? ticket : undefined;
}

export function requireBarberOnShift(day: QueueDay, barberId: string): BarberDayState {
  const barber = day.barbers[barberId];
  if (!barber || barber.status === 'off') throw new DomainError('barber-not-on-shift');
  return barber;
}

/** Substitui tickets pelo id, preservando a ordem do agregado. */
export function replaceTickets(tickets: readonly Ticket[], replacements: readonly Ticket[]): Ticket[] {
  const byId = new Map(replacements.map((t) => [t.id, t]));
  return tickets.map((t) => byId.get(t.id) ?? t);
}
