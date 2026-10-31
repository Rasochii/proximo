import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  buildPublicQueue,
  callNext,
  DomainError,
  finishCurrent,
  joinQueue,
  leaveQueue,
  PROCESSED_HISTORY_LIMIT,
  removeTicket,
  setAcceptingEntries,
  setBarberStatus,
  undoLast,
  type DomainErrorCode,
  type JoinQueueCommand,
  type QueueDay,
} from '../src/domain';
import { advanceCmd, at, ctxAt, emptyDay, join, SATURDAY, shop, SUNDAY, uuid, withBarbers } from './fixtures';

const T10 = at(`${SATURDAY}T10:00`);

function throwsCode(fn: () => unknown, code: DomainErrorCode): void {
  assert.throws(fn, (e: unknown) => {
    assert.ok(e instanceof DomainError, `esperava DomainError, veio ${String(e)}`);
    assert.equal(e.code, code);
    return true;
  });
}

function joinCmd(overrides: Partial<JoinQueueCommand> = {}): JoinQueueCommand {
  return {
    requestId: uuid(),
    actorUid: 'u1',
    newTicketId: 't-u1',
    name: 'Lucas Martins',
    serviceId: 'corte',
    source: 'qr',
    preferredBarberId: null,
    activeTicket: null,
    ...overrides,
  };
}

const openDay = (): QueueDay => withBarbers(emptyDay(), T10, 'ze');

function ticketStatus(day: QueueDay, id: string): string | undefined {
  return day.tickets.find((t) => t.id === id)?.status;
}

describe('joinQueue', () => {
  it('cria o ticket com número sequencial, rótulo público e efeito de ticket ativo', () => {
    const outcome = joinQueue(openDay(), ctxAt(T10), joinCmd());
    assert.deepEqual(outcome.result, { ticketId: 't-u1', number: 1 });
    assert.equal(outcome.day.nextNumber, 2);
    assert.equal(outcome.day.tickets[0]?.label, 'Lucas M.');
    assert.equal(outcome.day.tickets[0]?.status, 'waiting');
    assert.deepEqual(outcome.effects, [
      {
        type: 'activeTicket.set',
        uid: 'u1',
        ref: { shopId: shop.id, dateKey: SATURDAY, ticketId: 't-u1', number: 1 },
        onlyIfAbsent: false,
      },
    ]);
    assert.equal(outcome.replayed, false);
  });

  it('numera em sequência sem repetir', () => {
    let day = openDay();
    for (const uid of ['a', 'b', 'c']) day = join(day, { uid, nowMs: T10 });
    assert.deepEqual(day.tickets.map((t) => t.number), [1, 2, 3]);
  });

  it('é idempotente pelo requestId', () => {
    const cmd = joinCmd();
    const first = joinQueue(openDay(), ctxAt(T10), cmd);
    const replay = joinQueue(first.day, ctxAt(T10 + 1000), cmd);
    assert.equal(replay.replayed, true);
    assert.equal(replay.day, first.day);
    assert.deepEqual(replay.result, first.result);
    assert.deepEqual(replay.effects, []);
  });

  it('rejeita requestId reaproveitado por outro usuário', () => {
    const cmd = joinCmd();
    const first = joinQueue(openDay(), ctxAt(T10), cmd);
    throwsCode(() => joinQueue(first.day, ctxAt(T10), { ...cmd, actorUid: 'intruso' }), 'request-conflict');
  });

  it('limita o histórico de idempotência', () => {
    let day = openDay();
    for (let i = 0; i < PROCESSED_HISTORY_LIMIT + 10; i++) {
      day = setAcceptingEntries(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', accepting: true }).day;
    }
    assert.equal(day.processed.length, PROCESSED_HISTORY_LIMIT);
  });

  it('valida nome, serviço e barbeiro preferido', () => {
    throwsCode(() => joinQueue(openDay(), ctxAt(T10), joinCmd({ name: '1' })), 'invalid-name');
    throwsCode(() => joinQueue(openDay(), ctxAt(T10), joinCmd({ serviceId: 'nao-existe' })), 'invalid-service');
    throwsCode(() => joinQueue(openDay(), ctxAt(T10), joinCmd({ serviceId: 'pigmentacao' })), 'invalid-service');
    throwsCode(() => joinQueue(openDay(), ctxAt(T10), joinCmd({ preferredBarberId: 'joao' })), 'barber-not-found');
  });

  it('impede dois tickets ativos para a mesma pessoa', () => {
    const day = join(openDay(), { uid: 'u1', nowMs: T10 });
    throwsCode(() => joinQueue(day, ctxAt(T10), joinCmd({ newTicketId: 'outro' })), 'already-in-queue');
  });

  it('bloqueia quem tem ticket ativo em outra barbearia no mesmo dia, mas ignora referências antigas', () => {
    const elsewhereToday = { shopId: 'outra', dateKey: SATURDAY, ticketId: 'x', number: 3 };
    throwsCode(() => joinQueue(openDay(), ctxAt(T10), joinCmd({ activeTicket: elsewhereToday })), 'already-in-queue');

    const elsewhereYesterday = { ...elsewhereToday, dateKey: '2026-10-09' };
    assert.doesNotThrow(() => joinQueue(openDay(), ctxAt(T10), joinCmd({ activeTicket: elsewhereYesterday })));
  });

  it('libera nova entrada depois que o ticket anterior terminou', () => {
    let day = join(openDay(), { uid: 'u1', nowMs: T10 });
    day = leaveQueue(day, ctxAt(T10), { requestId: uuid(), actorUid: 'u1', ticketId: 't-u1' }).day;
    const ref = { shopId: shop.id, dateKey: SATURDAY, ticketId: 't-u1', number: 1 };
    assert.doesNotThrow(() => joinQueue(day, ctxAt(T10), joinCmd({ newTicketId: 't-u1-b', activeTicket: ref })));
  });

  it('respeita entrada fechada pelo barbeiro', () => {
    const day = setAcceptingEntries(openDay(), ctxAt(T10), { requestId: uuid(), actorUid: 'ze', accepting: false }).day;
    throwsCode(() => joinQueue(day, ctxAt(T10), joinCmd()), 'entries-closed');
  });

  it('respeita o horário de funcionamento', () => {
    throwsCode(() => joinQueue(emptyDay(SUNDAY), ctxAt(at(`${SUNDAY}T10:00`)), joinCmd()), 'closed-today');
    throwsCode(() => joinQueue(openDay(), ctxAt(at(`${SATURDAY}T08:20`)), joinCmd()), 'not-open-yet');
    assert.doesNotThrow(() => joinQueue(openDay(), ctxAt(at(`${SATURDAY}T08:31`)), joinCmd()));
    throwsCode(() => joinQueue(openDay(), ctxAt(at(`${SATURDAY}T18:46`)), joinCmd()), 'closing-soon');
  });

  it('fecha a entrada quando a fila já não cabe no expediente', () => {
    const now = at(`${SATURDAY}T17:30`);
    let day = withBarbers(emptyDay(), now, 'ze');
    // 17:30 → 18:00 → 18:30 → 19:00: o 4º já não seria atendido.
    for (const uid of ['a', 'b', 'c']) day = join(day, { uid, nowMs: now });
    throwsCode(() => joinQueue(day, ctxAt(now), joinCmd()), 'closing-soon');
  });

  it('sem barbeiro disponível não há previsão de espera e a entrada continua aberta', () => {
    const now = at(`${SATURDAY}T17:30`);
    let day = emptyDay();
    // A mesma fila do teste acima, mas ninguém iniciou o expediente: não dá para dizer que o 4º não cabe.
    for (const uid of ['a', 'b', 'c']) day = join(day, { uid, nowMs: now });
    assert.equal(joinQueue(day, ctxAt(now), joinCmd()).result.number, 4);
  });

  it('respeita o limite diário de tickets', () => {
    const tightShop = { ...shop, settings: { ...shop.settings, maxTicketsPerDay: 1 } };
    const day = join(openDay(), { uid: 'a', nowMs: T10 });
    throwsCode(() => joinQueue(day, ctxAt(T10, { shop: tightShop }), joinCmd()), 'queue-full');
  });

  it('detecta agregado de outro dia (erro de infraestrutura)', () => {
    throwsCode(() => joinQueue(emptyDay('2026-10-09'), ctxAt(T10), joinCmd()), 'day-mismatch');
  });
});

describe('leaveQueue', () => {
  it('cancela o próprio ticket e libera o ticket ativo', () => {
    const day = join(openDay(), { uid: 'u1', nowMs: T10 });
    const outcome = leaveQueue(day, ctxAt(T10), { requestId: uuid(), actorUid: 'u1', ticketId: 't-u1' });
    assert.equal(ticketStatus(outcome.day, 't-u1'), 'cancelled');
    assert.deepEqual(outcome.effects, [{ type: 'activeTicket.clear', uid: 'u1', ticketId: 't-u1' }]);
  });

  it('libera o barbeiro se o cliente desistir depois de chamado', () => {
    let day = join(openDay(), { uid: 'u1', nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    day = leaveQueue(day, ctxAt(T10), { requestId: uuid(), actorUid: 'u1', ticketId: 't-u1' }).day;
    assert.equal(day.barbers.ze?.currentTicketId, null);
  });

  it('só o dono pode sair e só de ticket ativo', () => {
    const day = join(openDay(), { uid: 'u1', nowMs: T10 });
    throwsCode(() => leaveQueue(day, ctxAt(T10), { requestId: uuid(), actorUid: 'u2', ticketId: 't-u1' }), 'not-ticket-owner');
    throwsCode(() => leaveQueue(day, ctxAt(T10), { requestId: uuid(), actorUid: 'u1', ticketId: 'x' }), 'ticket-not-found');
    const left = leaveQueue(day, ctxAt(T10), { requestId: uuid(), actorUid: 'u1', ticketId: 't-u1' }).day;
    throwsCode(() => leaveQueue(left, ctxAt(T10), { requestId: uuid(), actorUid: 'u1', ticketId: 't-u1' }), 'invalid-ticket-state');
  });

  it('repetir o mesmo pedido devolve o resultado guardado; reusar o requestId em outro comando é recusado', () => {
    const day = join(openDay(), { uid: 'u1', nowMs: T10 });
    const cmd = { requestId: uuid(), actorUid: 'u1', ticketId: 't-u1' };

    const first = leaveQueue(day, ctxAt(T10), cmd);
    const retry = leaveQueue(first.day, ctxAt(T10 + 20_000), cmd);
    assert.equal(retry.replayed, true);
    assert.deepEqual(retry.result, first.result);
    assert.deepEqual(retry.effects, []);
    assert.equal(retry.day, first.day);

    throwsCode(() => removeTicket(first.day, ctxAt(T10 + 30_000), { ...cmd, barberId: 'u1' }), 'request-conflict');
  });
});

describe('callNext ("Próximo!")', () => {
  const next = (day: QueueDay, nowMs: number, barberId = 'ze', outcome: 'done' | 'no_show' = 'done') =>
    callNext(day, ctxAt(nowMs), advanceCmd(day, barberId, outcome));

  it('exige expediente iniciado e não pausado', () => {
    throwsCode(() => next(emptyDay(), T10), 'barber-not-on-shift');
    const paused = setBarberStatus(openDay(), ctxAt(T10), {
      requestId: uuid(),
      actorUid: 'ze',
      barberId: 'ze',
      displayName: 'ZE',
      status: 'paused',
    }).day;
    throwsCode(() => next(paused, T10), 'barber-not-available');
  });

  it('chama o primeiro da fila e depois finaliza e chama o seguinte numa única operação', () => {
    let day = openDay();
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });

    const first = next(day, T10);
    assert.deepEqual(first.result, {
      finished: null,
      called: { ticketId: 't-a', number: 1, label: 'Cliente A.' },
      undoWindowSec: shop.settings.undoWindowSec,
    });
    assert.equal(first.day.barbers.ze?.currentTicketId, 't-a');

    const second = next(first.day, T10 + 25 * 60_000);
    assert.deepEqual(second.result.finished, { ticketId: 't-a', outcome: 'done' });
    assert.equal(second.result.called?.ticketId, 't-b');
    assert.equal(second.day.barbers.ze?.currentTicketId, 't-b');
    assert.equal(ticketStatus(second.day, 't-a'), 'done');
    assert.deepEqual(second.effects, [{ type: 'activeTicket.clear', uid: 'a', ticketId: 't-a' }]);
    assert.deepEqual(second.stats.corte, [{ ticketId: 't-a', minutes: 25 }]);
  });

  it('"Não veio" finaliza como no_show sem contaminar as estatísticas', () => {
    let day = join(openDay(), { uid: 'a', nowMs: T10 });
    day = next(day, T10).day;
    const outcome = next(day, T10 + 5 * 60_000, 'ze', 'no_show');
    assert.equal(ticketStatus(outcome.day, 't-a'), 'no_show');
    assert.deepEqual(outcome.stats, {});
  });

  it('fila vazia e ninguém em atendimento não altera nada nem cria desfazer', () => {
    const outcome = next(openDay(), T10);
    assert.deepEqual(outcome.result, { finished: null, called: null, undoWindowSec: shop.settings.undoWindowSec });
    assert.deepEqual(outcome.day.undo, {});
  });

  it('informa a janela de desfazer configurada pela barbearia', () => {
    const quickUndo = { ...shop, settings: { ...shop.settings, undoWindowSec: 40 } };
    const day = join(openDay(), { uid: 'a', nowMs: T10 });
    const outcome = callNext(day, ctxAt(T10, { shop: quickUndo }), advanceCmd(day));
    assert.equal(outcome.result.undoWindowSec, 40);
  });

  describe('conferência de quem está na cadeira', () => {
    const expecting = (day: QueueDay, expectedServingTicketId: string | null, outcome: 'done' | 'no_show' = 'done') =>
      callNext(day, ctxAt(T10 + 60_000), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome, expectedServingTicketId });

    /** Zé atendendo o cliente A, com B esperando. */
    function serving(): QueueDay {
      let day = openDay();
      for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
      return next(day, T10).day;
    }

    it('avança quando o console mostra a cadeira como ela está', () => {
      assert.equal(expecting(serving(), 't-a').result.called?.ticketId, 't-b');
      const idle = join(openDay(), { uid: 'a', nowMs: T10 });
      assert.equal(expecting(idle, null).result.called?.ticketId, 't-a');
    });

    it('recusa se o console acha a cadeira vazia e já há alguém nela', () => {
      // O "Próximo!" anterior foi aplicado, mas a tela não soube: avançar finalizaria o cliente A.
      const day = serving();
      throwsCode(() => expecting(day, null), 'serving-changed');
      throwsCode(() => expecting(day, null, 'no_show'), 'serving-changed');
    });

    it('recusa se o console mostra outra pessoa na cadeira', () => {
      throwsCode(() => expecting(serving(), 't-b'), 'serving-changed');
    });

    it('recusa se o console mostra alguém e a cadeira está vazia', () => {
      const idle = join(openDay(), { uid: 'a', nowMs: T10 });
      throwsCode(() => expecting(idle, 't-zzz'), 'serving-changed');
    });

    it('cada barbeiro responde pela própria cadeira', () => {
      let day = withBarbers(emptyDay(), T10, 'ze', 'joao');
      for (const uid of ['a', 'b', 'c', 'd']) day = join(day, { uid, nowMs: T10 });
      day = next(day, T10, 'ze').day;
      day = next(day, T10, 'joao').day;
      const by = (barberId: string, expectedServingTicketId: string | null, current = day) =>
        callNext(current, ctxAt(T10 + 60_000), { requestId: uuid(), actorUid: barberId, barberId, outcome: 'done', expectedServingTicketId });

      // Zé não avança olhando para a cadeira do João.
      throwsCode(() => by('ze', 't-b'), 'serving-changed');
      // O avanço do João não invalida o que o Zé vê na própria cadeira.
      const afterJoao = by('joao', 't-b').day;
      assert.equal(by('ze', 't-a', afterJoao).result.finished?.ticketId, 't-a');
    });

    it('se o cliente na cadeira sai da fila, a tela antiga é recusada e a nova segue', () => {
      const left = leaveQueue(serving(), ctxAt(T10 + 30_000), { requestId: uuid(), actorUid: 'a', ticketId: 't-a' }).day;
      throwsCode(() => expecting(left, 't-a'), 'serving-changed');
      const outcome = expecting(left, null);
      assert.equal(outcome.result.finished, null);
      assert.equal(outcome.result.called?.ticketId, 't-b');
    });

    it('depois de desfazer, vale quem voltou para a cadeira', () => {
      const advanced = expecting(serving(), 't-a').day;
      const undone = undoLast(advanced, ctxAt(T10 + 65_000), { requestId: uuid(), actorUid: 'ze', barberId: 'ze' }).day;
      throwsCode(() => expecting(undone, 't-b'), 'serving-changed');
      assert.equal(expecting(undone, 't-a').result.called?.ticketId, 't-b');
    });

    it('a nova tentativa do mesmo pedido devolve o resultado, mesmo com a cadeira já diferente', () => {
      const idle = join(openDay(), { uid: 'a', nowMs: T10 });
      const cmd = { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done', expectedServingTicketId: null } as const;
      const first = callNext(idle, ctxAt(T10), cmd);
      const retry = callNext(first.day, ctxAt(T10 + 20_000), cmd);
      assert.equal(retry.replayed, true);
      assert.deepEqual(retry.result, first.result);
      assert.equal(retry.day, first.day);
    });
  });

  it('dois barbeiros nunca chamam o mesmo cliente', () => {
    let day = withBarbers(emptyDay(), T10, 'ze', 'joao');
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
    const byZe = next(day, T10, 'ze');
    const byJoao = next(byZe.day, T10, 'joao');
    assert.equal(byZe.result.called?.ticketId, 't-a');
    assert.equal(byJoao.result.called?.ticketId, 't-b');
  });

  it('respeita a preferência por barbeiro, pulando para o próximo compatível', () => {
    let day = withBarbers(emptyDay(), T10, 'ze', 'joao');
    day = join(day, { uid: 'a', nowMs: T10, preferredBarberId: 'joao' });
    day = join(day, { uid: 'b', nowMs: T10 });
    assert.equal(next(day, T10, 'ze').result.called?.ticketId, 't-b');
    assert.equal(next(day, T10, 'joao').result.called?.ticketId, 't-a');
  });
});

describe('finishCurrent', () => {
  it('finaliza sem chamar ninguém, mesmo com a fila cheia', () => {
    let day = openDay();
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    const outcome = finishCurrent(day, ctxAt(T10 + 20 * 60_000), advanceCmd(day));
    assert.equal(outcome.result.called, null);
    assert.equal(ticketStatus(outcome.day, 't-b'), 'waiting');
    assert.equal(outcome.day.barbers.ze?.currentTicketId, null);
  });

  it('exige atendimento em andamento', () => {
    throwsCode(
      () => finishCurrent(openDay(), ctxAt(T10), advanceCmd(openDay())),
      'nothing-to-finish',
    );
  });

  it('exige expediente iniciado', () => {
    throwsCode(
      () => finishCurrent(emptyDay(), ctxAt(T10), advanceCmd(emptyDay())),
      'barber-not-on-shift',
    );
  });

  it('recusa se o console mostra na cadeira alguém que não está mais lá', () => {
    let day = openDay();
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    const finish = (current: QueueDay, expectedServingTicketId: string | null) =>
      finishCurrent(current, ctxAt(T10 + 60_000), {
        requestId: uuid(),
        actorUid: 'ze',
        barberId: 'ze',
        outcome: 'done',
        expectedServingTicketId,
      });

    throwsCode(() => finish(day, 't-b'), 'serving-changed');
    const finished = finish(day, 't-a');
    assert.equal(finished.result.finished?.ticketId, 't-a');
    // A cadeira esvaziou: quem ainda vê o cliente A recebe "a fila mudou", não "nada a finalizar".
    throwsCode(() => finish(finished.day, 't-a'), 'serving-changed');
    // Quem já vê a cadeira vazia recebe o motivo de sempre.
    throwsCode(() => finish(finished.day, null), 'nothing-to-finish');
  });

  it('repetir o mesmo pedido devolve o resultado guardado; reusar o requestId em outro comando é recusado', () => {
    let day = openDay();
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    const cmd = { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done', expectedServingTicketId: 't-a' } as const;

    const first = finishCurrent(day, ctxAt(T10 + 60_000), cmd);
    const retry = finishCurrent(first.day, ctxAt(T10 + 80_000), cmd);
    assert.equal(retry.replayed, true);
    assert.deepEqual(retry.result, first.result);
    assert.equal(retry.day, first.day);

    throwsCode(() => callNext(first.day, ctxAt(T10 + 90_000), cmd), 'request-conflict');
  });
});

describe('undoLast', () => {
  function scenario(): { day: QueueDay; at: number } {
    let day = openDay();
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    const at2 = T10 + 25 * 60_000;
    const ctx = ctxAt(at2);
    const outcome = callNext(day, ctx, advanceCmd(day));
    return { day: { ...outcome.day }, at: at2 };
  }
  const undo = (day: QueueDay, nowMs: number, stats = {}) =>
    undoLast(day, ctxAt(nowMs, { stats }), { requestId: uuid(), actorUid: 'ze', barberId: 'ze' });

  it('restaura tickets, barbeiro e estatísticas', () => {
    const { day, at: when } = scenario();
    const stats = { corte: [{ ticketId: 't-a', minutes: 25 }] };
    const outcome = undo(day, when + 3000, stats);
    assert.equal(ticketStatus(outcome.day, 't-a'), 'called');
    assert.equal(ticketStatus(outcome.day, 't-b'), 'waiting');
    assert.equal(outcome.day.barbers.ze?.currentTicketId, 't-a');
    assert.deepEqual(outcome.stats, { corte: [] });
    assert.deepEqual(outcome.effects, [
      {
        type: 'activeTicket.set',
        uid: 'a',
        ref: { shopId: shop.id, dateKey: SATURDAY, ticketId: 't-a', number: 1 },
        onlyIfAbsent: true,
      },
    ]);
    assert.deepEqual(outcome.day.undo, {});
    throwsCode(() => undo(outcome.day, when + 4000), 'nothing-to-undo');
  });

  it('expira depois da janela configurada (+ folga de rede)', () => {
    const { day, at: when } = scenario();
    const windowMs = shop.settings.undoWindowSec * 1000;
    assert.doesNotThrow(() => undo(day, when + windowMs + 4000));
    throwsCode(() => undo(day, when + windowMs + 6000), 'undo-expired');
  });

  it('recusa se a fila mudou nesses tickets', () => {
    const { day, at: when } = scenario();
    const left = leaveQueue(day, ctxAt(when), { requestId: uuid(), actorUid: 'b', ticketId: 't-b' }).day;
    throwsCode(() => undo(left, when + 1000), 'undo-conflict');
  });

  it('não é afetado por mudanças em outros tickets', () => {
    const { day, at: when } = scenario();
    const withNewcomer = join(day, { uid: 'c', nowMs: when });
    assert.doesNotThrow(() => undo(withNewcomer, when + 1000));
  });

  it('recusa reabrir o atendimento de quem já voltou para a fila', () => {
    // A foi finalizado e entrou de novo: reabrir o atendimento o deixaria com dois tickets ativos.
    const { day, at: when } = scenario();
    const rejoined = joinQueue(day, ctxAt(when + 1000), joinCmd({ actorUid: 'a', newTicketId: 't-a2' })).day;
    throwsCode(() => undo(rejoined, when + 2000), 'undo-conflict');

    // Se ele desiste do ticket novo, não há mais duplicidade e o desfazer volta a valer.
    const left = leaveQueue(rejoined, ctxAt(when + 3000), { requestId: uuid(), actorUid: 'a', ticketId: 't-a2' }).day;
    assert.equal(ticketStatus(undo(left, when + 4000).day, 't-a'), 'called');
  });

  it('repetir o mesmo pedido devolve o resultado guardado; reusar o requestId em outro comando é recusado', () => {
    const { day, at: when } = scenario();
    const cmd = { requestId: uuid(), actorUid: 'ze', barberId: 'ze' };

    const first = undoLast(day, ctxAt(when + 1000), cmd);
    // Sem a guarda de idempotência, esta segunda chamada seria recusada com `nothing-to-undo`.
    const retry = undoLast(first.day, ctxAt(when + 2000), cmd);
    assert.equal(retry.replayed, true);
    assert.deepEqual(retry.result, first.result);
    assert.deepEqual(retry.effects, []);
    assert.equal(retry.day, first.day);

    throwsCode(() => removeTicket(first.day, ctxAt(when + 3000), { ...cmd, ticketId: 't-b' }), 'request-conflict');
  });
});

describe('removeTicket', () => {
  it('remove um ticket aguardando e libera o ticket ativo do cliente', () => {
    const day = join(openDay(), { uid: 'troll', nowMs: T10 });
    const outcome = removeTicket(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', ticketId: 't-troll' });
    assert.equal(ticketStatus(outcome.day, 't-troll'), 'removed');
    assert.deepEqual(outcome.effects, [{ type: 'activeTicket.clear', uid: 'troll', ticketId: 't-troll' }]);
  });

  it('o dono pode remover mesmo fora do expediente', () => {
    const day = join(openDay(), { uid: 'troll', nowMs: T10 });
    const outcome = removeTicket(day, ctxAt(T10), { requestId: uuid(), actorUid: 'dono', barberId: 'dono', ticketId: 't-troll' });
    assert.equal(ticketStatus(outcome.day, 't-troll'), 'removed');
  });

  it('não remove ticket já chamado', () => {
    let day = join(openDay(), { uid: 'a', nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    throwsCode(
      () => removeTicket(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', ticketId: 't-a' }),
      'invalid-ticket-state',
    );
  });

  it('repetir o mesmo pedido devolve o resultado guardado; reusar o requestId em outro comando é recusado', () => {
    const day = join(openDay(), { uid: 'troll', nowMs: T10 });
    const cmd = { requestId: uuid(), actorUid: 'ze', barberId: 'ze', ticketId: 't-troll' };

    const first = removeTicket(day, ctxAt(T10), cmd);
    // Sem a guarda de idempotência, esta segunda chamada seria recusada com `invalid-ticket-state`.
    const retry = removeTicket(first.day, ctxAt(T10 + 20_000), cmd);
    assert.equal(retry.replayed, true);
    assert.deepEqual(retry.result, first.result);
    assert.deepEqual(retry.effects, []);
    assert.equal(retry.day, first.day);

    throwsCode(() => undoLast(first.day, ctxAt(T10 + 30_000), cmd), 'request-conflict');
  });
});

describe('setBarberStatus', () => {
  const status = (day: QueueDay, value: 'available' | 'paused' | 'off', nowMs = T10) =>
    setBarberStatus(day, ctxAt(nowMs), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', displayName: 'Zé', status: value });

  it('não encerra o expediente com cliente em atendimento', () => {
    let day = join(openDay(), { uid: 'a', nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;
    throwsCode(() => status(day, 'off'), 'finish-current-first');
    assert.doesNotThrow(() => status(day, 'paused'));
  });

  it('só o ticket que segue em atendimento impede encerrar o expediente', () => {
    let day = join(openDay(), { uid: 'a', nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;

    // Agregado inconsistente de propósito: o barbeiro aponta para um ticket que não existe.
    const barbers = { ...day.barbers, ze: { ...day.barbers.ze!, currentTicketId: 't-sumiu' } };
    const closed = status({ ...day, barbers }, 'off').day;

    assert.equal(closed.barbers.ze?.status, 'off');
    assert.equal(closed.barbers.ze?.currentTicketId, null);
  });

  it('preserva o início do status quando não muda', () => {
    const day = status(emptyDay(), 'available', T10).day;
    assert.equal(status(day, 'available', T10 + 60_000).day.barbers.ze?.statusSince, T10);
    assert.equal(status(day, 'paused', T10 + 60_000).day.barbers.ze?.statusSince, T10 + 60_000);
  });

  it('repetir o mesmo pedido devolve o resultado guardado; reusar o requestId em outro comando é recusado', () => {
    const cmd = { requestId: uuid(), actorUid: 'ze', barberId: 'ze', displayName: 'Zé', status: 'paused' } as const;

    const first = setBarberStatus(openDay(), ctxAt(T10), cmd);
    const retry = setBarberStatus(first.day, ctxAt(T10 + 20_000), cmd);
    assert.equal(retry.replayed, true);
    assert.deepEqual(retry.result, first.result);
    assert.equal(retry.day, first.day);

    throwsCode(() => undoLast(first.day, ctxAt(T10 + 30_000), cmd), 'request-conflict');
  });
});

describe('setAcceptingEntries', () => {
  it('fecha e reabre a entrada, e quem já está na fila continua nela', () => {
    const day = join(openDay(), { uid: 'a', nowMs: T10 });
    const closed = setAcceptingEntries(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', accepting: false });
    assert.deepEqual(closed.result, { accepting: false });
    assert.equal(closed.day.acceptingEntries, false);
    assert.equal(ticketStatus(closed.day, 't-a'), 'waiting');

    const reopened = setAcceptingEntries(closed.day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', accepting: true });
    assert.equal(reopened.day.acceptingEntries, true);
    assert.doesNotThrow(() => joinQueue(reopened.day, ctxAt(T10), joinCmd()));
  });

  it('repetir o mesmo pedido devolve o resultado guardado; reusar o requestId em outro comando é recusado', () => {
    const cmd = { requestId: uuid(), actorUid: 'ze', accepting: false };

    const first = setAcceptingEntries(openDay(), ctxAt(T10), cmd);
    const retry = setAcceptingEntries(first.day, ctxAt(T10 + 20_000), cmd);
    assert.equal(retry.replayed, true);
    assert.deepEqual(retry.result, first.result);
    assert.equal(retry.day, first.day);

    throwsCode(() => undoLast(first.day, ctxAt(T10 + 30_000), { ...cmd, barberId: 'ze' }), 'request-conflict');
  });
});

describe('buildPublicQueue', () => {
  it('um dia já encerrado, projetado depois, nasce vencido', () => {
    const day = openDay();
    const sunday = at('2026-10-11T08:00');

    const view = buildPublicQueue(day, ctxAt(sunday));

    assert.equal(view.dateKey, SATURDAY);
    assert.equal(view.validUntil, sunday);
  });

  it('expõe posição, ETA e quem está sendo atendido sem vazar dados pessoais', () => {
    let day = openDay();
    for (const uid of ['a', 'b', 'c']) day = join(day, { uid, name: `Fulano ${uid} Silva`, nowMs: T10 });
    day = callNext(day, ctxAt(T10), advanceCmd(day)).day;

    const view = buildPublicQueue(day, ctxAt(T10 + 10 * 60_000));
    assert.equal(view.waitingCount, 2);
    assert.deepEqual(
      view.waiting.map((w) => [w.position, w.label, w.eta]),
      [
        [1, 'Fulano S.', { kind: 'estimated', startsInMin: 20 }],
        [2, 'Fulano S.', { kind: 'estimated', startsInMin: 50 }],
      ],
    );
    assert.deepEqual(view.nowServing, [{ ticketId: 't-a', number: 1, label: 'Fulano S.', barberId: 'ze' }]);
    assert.deepEqual(view.barbers, [{ id: 'ze', displayName: 'ZE', status: 'available', servingNumber: 1 }]);
    assert.equal(view.entry.open, true);
    // Vale até o fim do dia da barbearia (meia-noite em São Paulo), não até a meia-noite UTC.
    assert.equal(view.validUntil, at('2026-10-11T00:00'));

    const serialized = JSON.stringify(view);
    for (const secret of ['customerUid', 'displayName":"Fulano', '"a"', 'Silva']) {
      assert.equal(serialized.includes(secret), false, `vazou ${secret}`);
    }
  });
});
