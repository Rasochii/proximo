/**
 * Modelo do domínio da fila. Tipos imutáveis, sem dependência de Firebase.
 * Datas são epoch em milissegundos; horários do dia são "HH:mm" no fuso da barbearia.
 */

export const WEEKDAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;
export type WeekdayKey = (typeof WEEKDAYS)[number];

/** Intervalo de funcionamento, ex.: { start: '09:00', end: '12:00' }. */
export interface TimeInterval {
  readonly start: string;
  readonly end: string;
}

/** Horário semanal. Os "intervalos fixos" (almoço etc.) são as lacunas entre os períodos. */
export type WeeklySchedule = Readonly<Record<WeekdayKey, readonly TimeInterval[]>>;

export interface Service {
  readonly id: string;
  readonly name: string;
  readonly defaultDurationMin: number;
  readonly active: boolean;
}

export interface ShopSettings {
  /** Fecha a entrada X minutos antes do último fechamento do dia. */
  readonly closeEntryMinutesBefore: number;
  /** Abre a entrada X minutos antes da primeira abertura do dia. */
  readonly openEntryMinutesBefore: number;
  readonly maxTicketsPerDay: number;
  readonly undoWindowSec: number;
}

export const DEFAULT_SHOP_SETTINGS: ShopSettings = {
  closeEntryMinutesBefore: 15,
  openEntryMinutesBefore: 30,
  maxTicketsPerDay: 200,
  undoWindowSec: 15,
};

export interface Shop {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  /** Fuso IANA, ex.: 'America/Sao_Paulo'. */
  readonly timezone: string;
  readonly schedule: WeeklySchedule;
  readonly services: readonly Service[];
  readonly settings: ShopSettings;
}

export const TICKET_STATUSES = ['waiting', 'called', 'done', 'no_show', 'cancelled', 'removed'] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];
export type ActiveTicketStatus = Extract<TicketStatus, 'waiting' | 'called'>;
export type FinishOutcome = Extract<TicketStatus, 'done' | 'no_show'>;

export const TICKET_SOURCES = ['link', 'qr', 'app', 'counter'] as const;
export type TicketSource = (typeof TICKET_SOURCES)[number];

export interface Ticket {
  readonly id: string;
  readonly number: number;
  /** Nome saneado completo, visível só para a equipe. */
  readonly displayName: string;
  /** Rótulo público minimizado, ex.: "Lucas M.". */
  readonly label: string;
  readonly customerUid: string;
  readonly serviceId: string;
  readonly preferredBarberId: string | null;
  readonly status: TicketStatus;
  readonly source: TicketSource;
  readonly createdAt: number;
  readonly calledAt: number | null;
  readonly finishedAt: number | null;
  readonly calledBy: string | null;
}

export const BARBER_STATUSES = ['available', 'paused', 'off'] as const;
export type BarberStatus = (typeof BARBER_STATUSES)[number];

/** Estado de um barbeiro no dia. */
export interface BarberDayState {
  readonly id: string;
  readonly displayName: string;
  readonly status: BarberStatus;
  readonly currentTicketId: string | null;
  readonly statusSince: number;
}

export type UndoableCommand = 'callNext' | 'finishCurrent';

export interface UndoSnapshot {
  readonly tickets: readonly Ticket[];
  readonly barber: BarberDayState;
}

/** Último comando desfazível de um barbeiro. */
export interface UndoEntry {
  readonly requestId: string;
  readonly command: UndoableCommand;
  readonly at: number;
  readonly before: UndoSnapshot;
  readonly after: UndoSnapshot;
}

export type CommandName =
  | 'joinQueue'
  | 'leaveQueue'
  | 'callNext'
  | 'finishCurrent'
  | 'undoLast'
  | 'removeTicket'
  | 'setBarberStatus'
  | 'setAcceptingEntries';

/** Registro para idempotência: o mesmo `requestId` devolve o mesmo resultado. */
export interface ProcessedRequest {
  readonly requestId: string;
  readonly actorUid: string;
  readonly command: CommandName;
  readonly at: number;
  readonly result: unknown;
}

/** Agregado: a fila de um dia de uma barbearia (ADR 0003). */
export interface QueueDay {
  readonly shopId: string;
  readonly dateKey: string;
  readonly acceptingEntries: boolean;
  readonly nextNumber: number;
  readonly tickets: readonly Ticket[];
  readonly barbers: Readonly<Record<string, BarberDayState>>;
  readonly undo: Readonly<Record<string, UndoEntry>>;
  readonly processed: readonly ProcessedRequest[];
  readonly version: number;
  readonly updatedAt: number;
}

export interface DurationSample {
  readonly ticketId: string;
  readonly minutes: number;
}

/** Últimas durações reais por serviço (alimenta o ETA). */
export type ServiceStats = Readonly<Record<string, readonly DurationSample[]>>;

/** Referência ao ticket ativo de um usuário (garante 1 ticket ativo por pessoa). */
export interface ActiveTicketRef {
  readonly shopId: string;
  readonly dateKey: string;
  readonly ticketId: string;
  readonly number: number;
}

/** Efeitos colaterais que a camada de infraestrutura aplica na mesma transação. */
export type Effect =
  | { readonly type: 'activeTicket.set'; readonly uid: string; readonly ref: ActiveTicketRef; readonly onlyIfAbsent: boolean }
  | { readonly type: 'activeTicket.clear'; readonly uid: string; readonly ticketId: string };
