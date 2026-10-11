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
import { at, ctxAt, emptyDay, join, SATURDAY, shop, SUNDAY, uuid, withBarbers } from './fixtures';

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
    day = callNext(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }).day;
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
});

describe('callNext ("Próximo!")', () => {
  const next = (day: QueueDay, nowMs: number, barberId = 'ze', outcome: 'done' | 'no_show' = 'done') =>
    callNext(day, ctxAt(nowMs), { requestId: uuid(), actorUid: barberId, barberId, outcome });

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
    assert.deepEqual(first.result, { finished: null, called: { ticketId: 't-a', number: 1, label: 'Cliente A.' } });
    assert.equal(first.day.barbers.ze?.currentTicketId, 't-a');

    const second = next(first.day, T10 + 25 * 60_000);
    assert.deepEqual(second.result.finished, { ticketId: 't-a', outcome: 'done' });
    assert.equal(second.result.called?.ticketId, 't-b');
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
    assert.deepEqual(outcome.result, { finished: null, called: null });
    assert.deepEqual(outcome.day.undo, {});
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
    day = callNext(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }).day;
    const outcome = finishCurrent(day, ctxAt(T10 + 20 * 60_000), {
      requestId: uuid(),
      actorUid: 'ze',
      barberId: 'ze',
      outcome: 'done',
    });
    assert.equal(outcome.result.called, null);
    assert.equal(ticketStatus(outcome.day, 't-b'), 'waiting');
    assert.equal(outcome.day.barbers.ze?.currentTicketId, null);
  });

  it('exige atendimento em andamento', () => {
    throwsCode(
      () => finishCurrent(openDay(), ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }),
      'nothing-to-finish',
    );
  });
});

describe('undoLast', () => {
  function scenario(): { day: QueueDay; at: number } {
    let day = openDay();
    for (const uid of ['a', 'b']) day = join(day, { uid, nowMs: T10 });
    day = callNext(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }).day;
    const at2 = T10 + 25 * 60_000;
    const ctx = ctxAt(at2);
    const outcome = callNext(day, ctx, { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' });
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
    day = callNext(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }).day;
    throwsCode(
      () => removeTicket(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', ticketId: 't-a' }),
      'invalid-ticket-state',
    );
  });
});

describe('setBarberStatus', () => {
  const status = (day: QueueDay, value: 'available' | 'paused' | 'off', nowMs = T10) =>
    setBarberStatus(day, ctxAt(nowMs), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', displayName: 'Zé', status: value });

  it('não encerra o expediente com cliente em atendimento', () => {
    let day = join(openDay(), { uid: 'a', nowMs: T10 });
    day = callNext(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }).day;
    throwsCode(() => status(day, 'off'), 'finish-current-first');
    assert.doesNotThrow(() => status(day, 'paused'));
  });

  it('preserva o início do status quando não muda', () => {
    const day = status(emptyDay(), 'available', T10).day;
    assert.equal(status(day, 'available', T10 + 60_000).day.barbers.ze?.statusSince, T10);
    assert.equal(status(day, 'paused', T10 + 60_000).day.barbers.ze?.statusSince, T10 + 60_000);
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
    day = callNext(day, ctxAt(T10), { requestId: uuid(), actorUid: 'ze', barberId: 'ze', outcome: 'done' }).day;

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
