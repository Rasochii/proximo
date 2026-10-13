import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  buildPublicQueue,
  callNext,
  DomainError,
  finishCurrent,
  joinQueue,
  leaveQueue,
  removeTicket,
  servingTicketOf,
  setBarberStatus,
  undoLast,
  type QueueDay,
} from '../src/domain';
import { at, ctxAt, emptyDay, SATURDAY, uuid } from './fixtures';

const BARBERS = ['ze', 'joao', 'ana'] as const;
const CUSTOMERS = ['a', 'b', 'c', 'd', 'e', 'f'] as const;
const STEPS = ['join', 'join', 'leave', 'next', 'next', 'finish', 'undo', 'undo', 'remove', 'status'] as const;

/** Gerador pseudoaleatório com semente fixa: as mesmas sequências em toda execução. */
function generator(seed: number): () => number {
  let state = seed;
  return () => {
    state = (state * 1664525 + 1013904223) % 4294967296;
    return state / 4294967296;
  };
}

/** O que o console mostra na cadeira do barbeiro: o que a projeção pública traz para ele. */
function shownToConsole(day: QueueDay, nowMs: number, barberId: string): string | null {
  return buildPublicQueue(day, ctxAt(nowMs)).nowServing.find((t) => t.barberId === barberId)?.ticketId ?? null;
}

/**
 * O servidor recusa um avanço quando o console mostra na cadeira alguém diferente de quem está
 * nela (`serving-changed`). Isso só é seguro se as duas visões nunca divergirem: se divergissem,
 * a recusa seria permanente, porque a tela "atualizada" continuaria mostrando o mesmo.
 *
 * O console lê a projeção (`nowServing`, pelo `calledBy` do ticket); o servidor usa
 * `servingTicketOf` (pelo `currentTicketId` do barbeiro). São dois campos do agregado, mantidos
 * iguais por todos os comandos. Este teste percorre sequências aleatórias de comandos e confere.
 */
describe('quem está na cadeira: agregado e projeção pública', () => {
  it('coincidem depois de qualquer sequência de comandos, e a tela em dia nunca é recusada', () => {
    let applied = 0;
    let advances = 0;

    for (let run = 1; run <= 300; run++) {
      const random = generator(run);
      const pick = <T>(items: readonly T[]): T => items[Math.floor(random() * items.length)]!;
      let day = emptyDay();
      let nowMs = at(`${SATURDAY}T10:00`);
      let tickets = 0;

      for (let step = 0; step < 50; step++) {
        nowMs += Math.floor(random() * 12_000);
        const ctx = ctxAt(nowMs);
        const barber = pick(BARBERS);
        const kind = pick(STEPS);
        const history = `sequência ${run}, passo ${step} (${kind} por ${barber})`;

        try {
          switch (kind) {
            case 'join': {
              const uid = pick(CUSTOMERS);
              day = joinQueue(day, ctx, {
                requestId: uuid(),
                actorUid: uid,
                newTicketId: `t${++tickets}-${uid}`,
                name: 'Cliente Teste',
                serviceId: 'corte',
                source: 'link',
                preferredBarberId: random() < 0.25 ? barber : null,
                activeTicket: null,
              }).day;
              break;
            }
            case 'leave': {
              const active = day.tickets.filter((t) => t.status === 'waiting' || t.status === 'called');
              if (active.length === 0) continue;
              const ticket = pick(active);
              day = leaveQueue(day, ctx, { requestId: uuid(), actorUid: ticket.customerUid, ticketId: ticket.id }).day;
              break;
            }
            case 'next':
            case 'finish': {
              // Console em dia: manda exatamente o que a projeção mostra para este barbeiro.
              const cmd = {
                requestId: uuid(),
                actorUid: barber,
                barberId: barber,
                outcome: pick(['done', 'no_show'] as const),
                expectedServingTicketId: shownToConsole(day, nowMs, barber),
              };
              try {
                day = (kind === 'next' ? callNext(day, ctx, cmd) : finishCurrent(day, ctx, cmd)).day;
                advances += 1;
              } catch (error) {
                assert.ok(
                  !(error instanceof DomainError && error.code === 'serving-changed'),
                  `tela em dia recusada na ${history}`,
                );
                throw error;
              }
              break;
            }
            case 'undo':
              day = undoLast(day, ctx, { requestId: uuid(), actorUid: barber, barberId: barber }).day;
              break;
            case 'remove': {
              if (day.tickets.length === 0) continue;
              const ticketId = pick(day.tickets).id;
              day = removeTicket(day, ctx, { requestId: uuid(), actorUid: barber, barberId: barber, ticketId }).day;
              break;
            }
            case 'status':
              day = setBarberStatus(day, ctx, {
                requestId: uuid(),
                actorUid: barber,
                barberId: barber,
                displayName: barber,
                status: pick(['available', 'available', 'paused', 'off'] as const),
              }).day;
              break;
          }
        } catch (error) {
          // Recusas de regra fazem parte do sorteio (pausado, nada a desfazer, fila fechada...).
          if (error instanceof DomainError) continue;
          throw error;
        }
        applied += 1;

        for (const state of Object.values(day.barbers)) {
          assert.equal(
            servingTicketOf(day, state)?.id ?? null,
            shownToConsole(day, nowMs, state.id),
            `agregado e projeção divergem para ${state.id} na ${history}`,
          );
          assert.equal(
            state.currentTicketId,
            servingTicketOf(day, state)?.id ?? null,
            `${state.id} aponta para um ticket que não está em atendimento na ${history}`,
          );
        }
      }
    }

    // Garante que o sorteio exercitou de fato os comandos, e não só recusas.
    assert.ok(applied > 3000, `poucos comandos aplicados: ${applied}`);
    assert.ok(advances > 500, `poucos avanços aplicados: ${advances}`);
  });
});
