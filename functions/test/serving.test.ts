import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  buildPublicQueue,
  callNext,
  DomainError,
  finishCurrent,
  isActive,
  joinQueue,
  leaveQueue,
  removeTicket,
  servingTicketOf,
  setBarberStatus,
  undoLast,
  type CommandOutcome,
  type QueueDay,
  type ServiceStats,
} from '../src/domain';
import { advanceCmd, at, ctxAt, emptyDay, SATURDAY, uuid, withBarbers } from './fixtures';

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
 * Por isso as duas saem de `servingTicketOf`, e compará-las passa por construção. O que este teste
 * protege é a estrutura por baixo: sequências aleatórias de comandos nunca podem deixar um ticket
 * chamado sem exatamente um barbeiro apontando para ele, um cliente com dois tickets ativos, o
 * `activeTickets` dele apontando para outro lugar, nem uma amostra de duração de quem não foi atendido.
 */
describe('quem está na cadeira: agregado e projeção pública', () => {
  it('a projeção segue o barbeiro, e não o `calledBy`, mesmo se os dois divergirem', () => {
    const nowMs = at(`${SATURDAY}T10:00`);
    const ctx = ctxAt(nowMs);
    const joined = joinQueue(withBarbers(emptyDay(), nowMs, 'ze'), ctx, {
      requestId: uuid(),
      actorUid: 'a',
      newTicketId: 't-a',
      name: 'Cliente A',
      serviceId: 'corte',
      source: 'qr',
      preferredBarberId: null,
      activeTicket: null,
    }).day;
    const called = callNext(joined, ctx, advanceCmd(joined)).day;
    assert.equal(shownToConsole(called, nowMs, 'ze'), 't-a');

    // Agregado inconsistente de propósito: o ticket segue chamado, mas o barbeiro não aponta mais para ele.
    const barbers = { ...called.barbers, ze: { ...called.barbers.ze!, currentTicketId: null } };
    const diverged = { ...called, barbers };

    // O console mostra a cadeira vazia, e o servidor concorda: nada de recusa eterna.
    assert.equal(shownToConsole(diverged, nowMs, 'ze'), null);
    assert.equal(servingTicketOf(diverged, diverged.barbers.ze), undefined);
    // O ticket continua aparecendo como em atendimento, só que sem barbeiro.
    assert.deepEqual(
      buildPublicQueue(diverged, ctx).nowServing.map((t) => [t.ticketId, t.barberId]),
      [['t-a', null]],
    );
  });

  it('coincidem depois de qualquer sequência de comandos, e a tela em dia nunca é recusada', () => {
    let applied = 0;
    let advances = 0;

    for (let run = 1; run <= 300; run++) {
      const random = generator(run);
      const pick = <T>(items: readonly T[]): T => items[Math.floor(random() * items.length)]!;
      let day = emptyDay();
      let nowMs = at(`${SATURDAY}T10:00`);
      let tickets = 0;
      let stats: ServiceStats = {};
      /** `activeTickets/{uid}` como a infraestrutura deixaria: o id do ticket de cada cliente. */
      const activeTickets = new Map<string, string>();

      const apply = (outcome: CommandOutcome<unknown>): void => {
        ({ day, stats } = outcome);
        for (const effect of outcome.effects) {
          if (effect.type === 'activeTicket.set') {
            if (!effect.onlyIfAbsent || !activeTickets.has(effect.uid)) activeTickets.set(effect.uid, effect.ref.ticketId);
          } else if (activeTickets.get(effect.uid) === effect.ticketId) {
            activeTickets.delete(effect.uid);
          }
        }
      };

      for (let step = 0; step < 50; step++) {
        nowMs += Math.floor(random() * 12_000);
        const ctx = ctxAt(nowMs, { stats });
        const barber = pick(BARBERS);
        const kind = pick(STEPS);
        const history = `sequência ${run}, passo ${step} (${kind} por ${barber})`;

        try {
          switch (kind) {
            case 'join': {
              const uid = pick(CUSTOMERS);
              apply(
                joinQueue(day, ctx, {
                  requestId: uuid(),
                  actorUid: uid,
                  newTicketId: `t${++tickets}-${uid}`,
                  name: 'Cliente Teste',
                  serviceId: 'corte',
                  source: 'link',
                  preferredBarberId: random() < 0.25 ? barber : null,
                  activeTicket: null,
                }),
              );
              break;
            }
            case 'leave': {
              const active = day.tickets.filter((t) => t.status === 'waiting' || t.status === 'called');
              if (active.length === 0) continue;
              const ticket = pick(active);
              apply(leaveQueue(day, ctx, { requestId: uuid(), actorUid: ticket.customerUid, ticketId: ticket.id }));
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
                apply(kind === 'next' ? callNext(day, ctx, cmd) : finishCurrent(day, ctx, cmd));
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
              apply(undoLast(day, ctx, { requestId: uuid(), actorUid: barber, barberId: barber }));
              break;
            case 'remove': {
              if (day.tickets.length === 0) continue;
              const ticketId = pick(day.tickets).id;
              apply(removeTicket(day, ctx, { requestId: uuid(), actorUid: barber, barberId: barber, ticketId }));
              break;
            }
            case 'status':
              apply(
                setBarberStatus(day, ctx, {
                  requestId: uuid(),
                  actorUid: barber,
                  barberId: barber,
                  displayName: barber,
                  status: pick(['available', 'available', 'paused', 'off'] as const),
                }),
              );
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

        for (const ticket of day.tickets.filter((t) => t.status === 'called')) {
          const owners = Object.values(day.barbers).filter((b) => b.currentTicketId === ticket.id);
          assert.deepEqual(
            owners.map((b) => b.id),
            [ticket.calledBy],
            `${ticket.id} chamado sem exatamente um dono na ${history}`,
          );
        }

        const customers = day.tickets.filter(isActive).map((t) => t.customerUid);
        assert.equal(new Set(customers).size, customers.length, `cliente com dois tickets ativos na ${history}`);

        const expectedActive = day.tickets.filter(isActive).map((t) => [t.customerUid, t.id]);
        assert.deepEqual(
          [...activeTickets].sort(),
          expectedActive.sort(),
          `activeTickets diverge do agregado na ${history}`,
        );

        for (const sample of Object.values(stats).flat()) {
          const status = day.tickets.find((t) => t.id === sample.ticketId)?.status;
          assert.equal(status, 'done', `amostra de ${sample.ticketId} sem atendimento concluído na ${history}`);
        }
      }
    }

    // Garante que o sorteio exercitou de fato os comandos, e não só recusas.
    assert.ok(applied > 3000, `poucos comandos aplicados: ${applied}`);
    assert.ok(advances > 500, `poucos avanços aplicados: ${advances}`);
  });
});
