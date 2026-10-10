import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { estimateWaits, intervalsFor, type BarberDayState, type EtaInput, type EtaTicket } from '../src/domain';
import { shop } from './fixtures';

const intervals = intervalsFor(shop.schedule, 'sat'); // 09–12, 13–19
const NOW_MS = 1_000_000_000;

function barber(id: string, overrides: Partial<BarberDayState> = {}): BarberDayState {
  return { id, displayName: id, status: 'available', currentTicketId: null, statusSince: 0, ...overrides };
}

function ticket(number: number, overrides: Partial<EtaTicket> = {}): EtaTicket {
  return { id: `t${number}`, number, serviceId: 'corte', preferredBarberId: null, ...overrides };
}

function run(overrides: Partial<EtaInput>): Map<string, unknown> {
  return estimateWaits({
    waiting: [],
    barbers: [barber('a')],
    inService: [],
    intervals,
    nowMs: NOW_MS,
    nowMinute: 10 * 60,
    durationOf: (serviceId) => (serviceId === 'barba' ? 20 : 30),
    ...overrides,
  });
}

const est = (startsInMin: number) => ({ kind: 'estimated', startsInMin });

describe('estimateWaits', () => {
  it('um barbeiro atende em sequência, respeitando a duração de cada serviço', () => {
    const etas = run({ waiting: [ticket(1), ticket(2, { serviceId: 'barba' }), ticket(3)] });
    assert.deepEqual(etas.get('t1'), est(0));
    assert.deepEqual(etas.get('t2'), est(30));
    assert.deepEqual(etas.get('t3'), est(50));
  });

  it('ordena por número independentemente da ordem de entrada', () => {
    const etas = run({ waiting: [ticket(2), ticket(1)] });
    assert.deepEqual(etas.get('t1'), est(0));
    assert.deepEqual(etas.get('t2'), est(30));
  });

  it('dois barbeiros atendem em paralelo', () => {
    const etas = run({ barbers: [barber('a'), barber('b')], waiting: [1, 2, 3, 4].map((n) => ticket(n)) });
    assert.deepEqual(
      [1, 2, 3, 4].map((n) => etas.get(`t${n}`)),
      [est(0), est(0), est(30), est(30)],
    );
  });

  it('considera o tempo restante de quem está em atendimento', () => {
    const etas = run({
      barbers: [barber('a', { currentTicketId: 'x' })],
      inService: [{ id: 'x', serviceId: 'corte', calledAt: NOW_MS - 10 * 60_000 }],
      waiting: [ticket(1)],
    });
    assert.deepEqual(etas.get('t1'), est(20));
  });

  it('atendimento atrasado conta como "terminando agora"', () => {
    const etas = run({
      barbers: [barber('a', { currentTicketId: 'x' })],
      inService: [{ id: 'x', serviceId: 'corte', calledAt: NOW_MS - 45 * 60_000 }],
      waiting: [ticket(1)],
    });
    assert.deepEqual(etas.get('t1'), est(0));
  });

  it('pula o intervalo de almoço', () => {
    // Agora 11:20: t1 às 11:20, t2 às 11:50 (termina 12:20, atravessa o almoço), t3 às 13:00.
    const etas = run({ nowMinute: 11 * 60 + 20, waiting: [ticket(1), ticket(2), ticket(3)] });
    assert.deepEqual(etas.get('t2'), est(30));
    assert.deepEqual(etas.get('t3'), est(100));
  });

  it('antes de abrir, a espera conta a partir da abertura', () => {
    const etas = run({ nowMinute: 8 * 60 + 30, waiting: [ticket(1)] });
    assert.deepEqual(etas.get('t1'), est(30));
  });

  it('marca como beyond_closing quem não seria atendido hoje', () => {
    const etas = run({ nowMinute: 18 * 60 + 20, waiting: [ticket(1), ticket(2)] });
    assert.deepEqual(etas.get('t1'), est(0));
    assert.deepEqual(etas.get('t2'), est(30)); // começa 18:50, ainda dentro do expediente
    const late = run({ nowMinute: 18 * 60 + 40, waiting: [ticket(1), ticket(2)] });
    assert.deepEqual(late.get('t2'), { kind: 'beyond_closing' });
  });

  it('respeita a preferência por barbeiro sem travar os demais', () => {
    const etas = run({
      barbers: [barber('a'), barber('b')],
      waiting: [ticket(1, { preferredBarberId: 'b' }), ticket(2, { preferredBarberId: 'b' }), ticket(3)],
    });
    assert.deepEqual(etas.get('t1'), est(0)); // b
    assert.deepEqual(etas.get('t3'), est(0)); // a pega o primeiro compatível
    assert.deepEqual(etas.get('t2'), est(30)); // espera b
  });

  it('é unknown quando não há barbeiro compatível ativo', () => {
    assert.deepEqual(run({ barbers: [], waiting: [ticket(1)] }).get('t1'), { kind: 'unknown' });
    const etas = run({ waiting: [ticket(1, { preferredBarberId: 'ausente' })] });
    assert.deepEqual(etas.get('t1'), { kind: 'unknown' });
  });

  it('ignora barbeiros pausados ou fora do expediente', () => {
    const etas = run({ barbers: [barber('a', { status: 'paused' }), barber('b', { status: 'off' })], waiting: [ticket(1)] });
    assert.deepEqual(etas.get('t1'), { kind: 'unknown' });
  });
});
