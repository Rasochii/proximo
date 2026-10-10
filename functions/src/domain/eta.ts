import { alignToOpen, type MinuteInterval } from './schedule';
import type { BarberDayState, Ticket } from './types';

export type TicketEta =
  /** Começa a ser atendido em ~N minutos. */
  | { readonly kind: 'estimated'; readonly startsInMin: number }
  /** Não dá tempo de atender hoje. */
  | { readonly kind: 'beyond_closing' }
  /** Sem barbeiro ativo compatível para estimar. */
  | { readonly kind: 'unknown' };

/** Ticket mínimo para simulação (permite incluir um ticket "fantasma" de quem ainda vai entrar). */
export type EtaTicket = Pick<Ticket, 'id' | 'number' | 'serviceId' | 'preferredBarberId'>;

export interface EtaInput {
  /** Tickets aguardando, em qualquer ordem (a simulação ordena por número). */
  readonly waiting: readonly EtaTicket[];
  readonly barbers: readonly BarberDayState[];
  /** Tickets em atendimento, para saber quanto falta para cada barbeiro ficar livre. */
  readonly inService: readonly Pick<Ticket, 'id' | 'serviceId' | 'calledAt'>[];
  readonly intervals: readonly MinuteInterval[];
  readonly nowMs: number;
  /** Minuto local "agora" (no fuso da barbearia). */
  readonly nowMinute: number;
  readonly durationOf: (serviceId: string) => number;
}

interface SimServer {
  readonly id: string;
  freeAt: number;
}

/**
 * Estima o início de cada ticket por **simulação de eventos** (ADR 0005):
 * o barbeiro que fica livre primeiro pega o primeiro ticket compatível — a mesma regra do `callNext`.
 * Respeita os intervalos do horário (almoço) e o fechamento do dia.
 */
export function estimateWaits(input: EtaInput): Map<string, TicketEta> {
  const result = new Map<string, TicketEta>();
  const inServiceById = new Map(input.inService.map((t) => [t.id, t]));

  const servers: SimServer[] = input.barbers
    .filter((b) => b.status === 'available')
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((barber) => ({ id: barber.id, freeAt: initialFreeAt(barber, inServiceById, input) }));
  const initialServerIds = new Set(servers.map((s) => s.id));

  const pending = [...input.waiting].sort((a, b) => a.number - b.number);

  while (pending.length > 0 && servers.length > 0) {
    const serverIndex = indexOfEarliest(servers);
    const server = servers[serverIndex]!;
    const start = alignToOpen(input.intervals, server.freeAt);
    const ticketIndex = pending.findIndex((t) => t.preferredBarberId === null || t.preferredBarberId === server.id);

    if (start === null || ticketIndex === -1) {
      // Este barbeiro não atende mais ninguém hoje (fechou ou não há ticket compatível).
      servers.splice(serverIndex, 1);
      continue;
    }

    const [ticket] = pending.splice(ticketIndex, 1);
    result.set(ticket!.id, { kind: 'estimated', startsInMin: Math.max(0, Math.round(start - input.nowMinute)) });
    server.freeAt = start + input.durationOf(ticket!.serviceId);
  }

  for (const ticket of pending) {
    const hasCompatibleServer =
      ticket.preferredBarberId === null ? initialServerIds.size > 0 : initialServerIds.has(ticket.preferredBarberId);
    // Se havia barbeiro compatível e ainda assim sobrou, é porque o expediente acabou.
    result.set(ticket.id, hasCompatibleServer ? { kind: 'beyond_closing' } : { kind: 'unknown' });
  }
  return result;
}

function initialFreeAt(
  barber: BarberDayState,
  inServiceById: ReadonlyMap<string, Pick<Ticket, 'serviceId' | 'calledAt'>>,
  input: EtaInput,
): number {
  const current = barber.currentTicketId ? inServiceById.get(barber.currentTicketId) : undefined;
  if (!current || current.calledAt === null) return input.nowMinute;
  const elapsedMin = Math.max(0, (input.nowMs - current.calledAt) / 60_000);
  const remainingMin = Math.max(0, input.durationOf(current.serviceId) - elapsedMin);
  return input.nowMinute + remainingMin;
}

function indexOfEarliest(servers: readonly SimServer[]): number {
  let best = 0;
  for (let i = 1; i < servers.length; i++) {
    if (servers[i]!.freeAt < servers[best]!.freeAt) best = i;
  }
  return best;
}
