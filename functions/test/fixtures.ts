import {
  createQueueDay,
  DEFAULT_SHOP_SETTINGS,
  joinQueue,
  servingTicketOf,
  setBarberStatus,
  type AdvanceCommand,
  type DayContext,
  type FinishOutcome,
  type QueueDay,
  type ServiceStats,
  type Shop,
} from '../src/domain';

/** Instante em São Paulo (UTC-3, sem horário de verão desde 2019). 2026-10-10 é sábado. */
export function at(localDateTime: string): number {
  return Date.parse(`${localDateTime}:00-03:00`);
}

export const SATURDAY = '2026-10-10';
export const SUNDAY = '2026-10-11';

const workday = [
  { start: '09:00', end: '12:00' },
  { start: '13:00', end: '19:00' },
];

export const shop: Shop = {
  id: 'barbearia-do-ze',
  name: 'Barbearia do Zé',
  slug: 'barbearia-do-ze',
  timezone: 'America/Sao_Paulo',
  schedule: { sun: [], mon: workday, tue: workday, wed: workday, thu: workday, fri: workday, sat: workday },
  services: [
    { id: 'corte', name: 'Corte', defaultDurationMin: 30, active: true },
    { id: 'barba', name: 'Barba', defaultDurationMin: 20, active: true },
    { id: 'pigmentacao', name: 'Pigmentação', defaultDurationMin: 60, active: false },
  ],
  settings: DEFAULT_SHOP_SETTINGS,
};

export function ctxAt(nowMs: number, overrides: Partial<DayContext> = {}): DayContext {
  return { nowMs, shop, stats: {}, ...overrides };
}

let counter = 0;
/** UUID v4 determinístico e válido para testes. */
export function uuid(): string {
  counter += 1;
  const hex = counter.toString(16).padStart(12, '0');
  return `00000000-0000-4000-8000-${hex}`;
}

export function emptyDay(dateKey = SATURDAY, nowMs = at(`${dateKey}T08:00`)): QueueDay {
  return createQueueDay(shop.id, dateKey, nowMs);
}

export function withBarbers(day: QueueDay, nowMs: number, ...ids: string[]): QueueDay {
  return ids.reduce(
    (current, id) =>
      setBarberStatus(current, ctxAt(nowMs), {
        requestId: uuid(),
        actorUid: id,
        barberId: id,
        displayName: id.toUpperCase(),
        status: 'available',
      }).day,
    day,
  );
}

/** Um avanço vindo de um console em dia: diz na cadeira exatamente quem está nela. */
export function advanceCmd(day: QueueDay, barberId = 'ze', outcome: FinishOutcome = 'done'): AdvanceCommand {
  const barber = day.barbers[barberId];
  return {
    requestId: uuid(),
    actorUid: barberId,
    barberId,
    outcome,
    expectedServingTicketId: (barber && servingTicketOf(day, barber)?.id) ?? null,
  };
}

export interface JoinOptions {
  readonly uid: string;
  readonly name?: string;
  readonly serviceId?: string;
  readonly preferredBarberId?: string | null;
  readonly nowMs: number;
  readonly stats?: ServiceStats;
}

export function join(day: QueueDay, options: JoinOptions): QueueDay {
  return joinQueue(day, ctxAt(options.nowMs, { stats: options.stats ?? {} }), {
    requestId: uuid(),
    actorUid: options.uid,
    newTicketId: `t-${options.uid}`,
    name: options.name ?? `Cliente ${options.uid.replace(/[^\p{L}]/gu, '') || 'X'}`,
    serviceId: options.serviceId ?? 'corte',
    source: 'link',
    preferredBarberId: options.preferredBarberId ?? null,
    activeTicket: null,
  }).day;
}
