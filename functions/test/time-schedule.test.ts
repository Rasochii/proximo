import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  alignToOpen,
  dayBounds,
  DomainError,
  intervalsFor,
  isValidTimeZone,
  parseHHmm,
  parseWeeklySchedule,
  toLocal,
} from '../src/domain';
import { at, shop } from './fixtures';

describe('toLocal', () => {
  it('converte para o fuso de São Paulo', () => {
    const local = toLocal(at('2026-10-10T09:30'), 'America/Sao_Paulo');
    assert.equal(local.dateKey, '2026-10-10');
    assert.equal(local.weekday, 'sat');
    assert.equal(local.minuteOfDay, 9 * 60 + 30);
  });

  it('vira o dia à meia-noite local, não à meia-noite UTC', () => {
    // 23:30 em SP = 02:30 UTC do dia seguinte
    const local = toLocal(at('2026-10-10T23:30'), 'America/Sao_Paulo');
    assert.equal(local.dateKey, '2026-10-10');
    assert.equal(local.minuteOfDay, 23 * 60 + 30);
  });

  it('respeita horário de verão em outros fusos', () => {
    // 8 de março de 2026: Nova York adianta o relógio às 2h (EST → EDT)
    const beforeDst = toLocal(Date.parse('2026-03-08T06:30:00Z'), 'America/New_York');
    const afterDst = toLocal(Date.parse('2026-03-08T12:00:00Z'), 'America/New_York');
    assert.equal(beforeDst.minuteOfDay, 1 * 60 + 30);
    assert.equal(afterDst.minuteOfDay, 8 * 60);
  });

  it('valida fusos IANA', () => {
    assert.equal(isValidTimeZone('America/Sao_Paulo'), true);
    assert.equal(isValidTimeZone('Mars/Olympus_Mons'), false);
  });
});

describe('parseHHmm', () => {
  it('aceita horários válidos e 24:00', () => {
    assert.equal(parseHHmm('00:00'), 0);
    assert.equal(parseHHmm('09:05'), 545);
    assert.equal(parseHHmm('23:59'), 1439);
    assert.equal(parseHHmm('24:00'), 1440);
  });

  it('rejeita formatos inválidos', () => {
    for (const value of ['9:00', '24:01', '12:60', 'aa:bb', '', '12:00:00']) {
      assert.equal(parseHHmm(value), null, value);
    }
  });
});

describe('parseWeeklySchedule', () => {
  it('ordena os períodos e preenche dias ausentes como fechados', () => {
    const schedule = parseWeeklySchedule({
      mon: [
        { start: '13:00', end: '18:00' },
        { start: '08:00', end: '12:00' },
      ],
    });
    assert.deepEqual(schedule.mon, [
      { start: '08:00', end: '12:00' },
      { start: '13:00', end: '18:00' },
    ]);
    assert.deepEqual(schedule.sun, []);
  });

  it('aceita período encostado no seguinte', () => {
    assert.doesNotThrow(() =>
      parseWeeklySchedule({
        tue: [
          { start: '08:00', end: '12:00' },
          { start: '12:00', end: '18:00' },
        ],
      }),
    );
  });

  const invalid: Record<string, unknown> = {
    'não objeto': [],
    nulo: null,
    'sobreposição': {
      mon: [
        { start: '08:00', end: '12:30' },
        { start: '12:00', end: '18:00' },
      ],
    },
    'início depois do fim': { mon: [{ start: '18:00', end: '08:00' }] },
    'início igual ao fim': { mon: [{ start: '08:00', end: '08:00' }] },
    'formato inválido': { mon: [{ start: '8h', end: '12h' }] },
    'dia não é lista': { mon: { start: '08:00', end: '12:00' } },
    'muitos períodos': { mon: Array.from({ length: 7 }, (_, i) => ({ start: `0${i}:00`, end: `0${i}:30` })) },
  };
  for (const [label, input] of Object.entries(invalid)) {
    it(`rejeita: ${label}`, () => {
      assert.throws(() => parseWeeklySchedule(input), (error: unknown) => {
        return error instanceof DomainError && error.code === 'invalid-schedule';
      });
    });
  }
});

describe('alignToOpen / dayBounds', () => {
  const intervals = intervalsFor(shop.schedule, 'sat'); // 09–12, 13–19

  it('mantém instantes dentro do expediente', () => {
    assert.equal(alignToOpen(intervals, 10 * 60), 10 * 60);
  });

  it('empurra para a abertura quando é cedo', () => {
    assert.equal(alignToOpen(intervals, 7 * 60), 9 * 60);
  });

  it('empurra para depois do almoço', () => {
    assert.equal(alignToOpen(intervals, 12 * 60 + 10), 13 * 60);
    assert.equal(alignToOpen(intervals, 12 * 60), 13 * 60);
  });

  it('retorna null depois do fechamento', () => {
    assert.equal(alignToOpen(intervals, 19 * 60), null);
  });

  it('calcula a primeira abertura e o último fechamento', () => {
    assert.deepEqual(dayBounds(intervals), { start: 9 * 60, end: 19 * 60 });
    assert.equal(dayBounds(intervalsFor(shop.schedule, 'sun')), null);
  });
});
