import type { TicketEta } from './eta';
import {
  calledTickets,
  estimateDay,
  evaluateEntry,
  servingTicketOf,
  waitingTickets,
  type DayContext,
  type EntryClosedReason,
} from './queueDay';
import { endOfLocalDayMs, toLocal } from './time';
import type { BarberStatus, QueueDay } from './types';

/**
 * Projeção pública da fila (`publicQueues/{shopId}`), lida em tempo real pelo cliente e pela TV.
 * Não contém UIDs de clientes, nomes completos nem telefones (LGPD — princípio da necessidade).
 * Exceção a resolver antes do primeiro deploy: `barberId` é o UID do barbeiro, porque o console
 * se reconhece por ele (ver "Decisões adiadas" em `docs/PLANO_DE_ACAO.md`).
 */
export interface PublicQueue {
  readonly shopId: string;
  readonly shopName: string;
  readonly slug: string;
  readonly dateKey: string;
  readonly entry: {
    readonly open: boolean;
    readonly reason: EntryClosedReason | null;
    readonly eta: TicketEta;
  };
  readonly barbers: readonly {
    readonly id: string;
    readonly displayName: string;
    readonly status: BarberStatus;
    readonly servingNumber: number | null;
  }[];
  readonly nowServing: readonly {
    readonly ticketId: string;
    readonly number: number;
    readonly label: string;
    readonly barberId: string | null;
  }[];
  readonly waiting: readonly {
    readonly ticketId: string;
    readonly number: number;
    readonly label: string;
    readonly serviceId: string;
    readonly preferredBarberId: string | null;
    readonly position: number;
    readonly eta: TicketEta;
  }[];
  readonly waitingCount: number;
  readonly version: number;
  readonly updatedAt: number;
  /**
   * Até quando esta projeção vale (epoch ms): o fim do dia no fuso da barbearia.
   * Ela só é regravada quando um comando roda; sem este prazo, a fila de ontem continuaria
   * aparecendo como a de hoje até a primeira ação do dia.
   */
  readonly validUntil: number;
}

export function buildPublicQueue(day: QueueDay, ctx: DayContext): PublicQueue {
  const etas = estimateDay(day, ctx);
  const called = calledTickets(day);
  const waiting = waitingTickets(day);
  // Quem atende cada ticket, pela mesma definição que confere o avanço (`serving-changed`): se a
  // projeção usasse outra fonte, uma divergência faria o console ser recusado para sempre.
  const servingBarber = new Map(
    Object.values(day.barbers).flatMap((barber) => {
      const ticket = servingTicketOf(day, barber);
      return ticket ? [[ticket.id, barber.id] as const] : [];
    }),
  );

  return {
    shopId: day.shopId,
    shopName: ctx.shop.name,
    slug: ctx.shop.slug,
    dateKey: day.dateKey,
    entry: evaluateEntry(day, ctx),
    barbers: Object.values(day.barbers)
      .filter((b) => b.status !== 'off')
      .sort((a, b) => a.displayName.localeCompare(b.displayName, 'pt-BR'))
      .map((b) => ({
        id: b.id,
        displayName: b.displayName,
        status: b.status,
        servingNumber: servingTicketOf(day, b)?.number ?? null,
      })),
    nowServing: called.map((t) => ({
      ticketId: t.id,
      number: t.number,
      label: t.label,
      barberId: servingBarber.get(t.id) ?? null,
    })),
    waiting: waiting.map((t, index) => ({
      ticketId: t.id,
      number: t.number,
      label: t.label,
      serviceId: t.serviceId,
      preferredBarberId: t.preferredBarberId,
      position: index + 1,
      eta: etas.get(t.id) ?? { kind: 'unknown' },
    })),
    waitingCount: waiting.length,
    version: day.version,
    updatedAt: day.updatedAt,
    validUntil: validUntilOf(day, ctx),
  };
}

/**
 * A projeção vale até o fim do dia do agregado. Os comandos sempre projetam o dia corrente; se um
 * dia já encerrado for projetado depois (por uma rotina de fechamento, por exemplo), a projeção
 * nasce vencida, para a fila de ontem nunca ser mostrada como a de hoje.
 */
function validUntilOf(day: QueueDay, ctx: DayContext): number {
  const { timezone } = ctx.shop;
  return toLocal(ctx.nowMs, timezone).dateKey === day.dateKey ? endOfLocalDayMs(ctx.nowMs, timezone) : ctx.nowMs;
}
