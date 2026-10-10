import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  consumeRateLimit,
  DomainError,
  expectedDurationMin,
  MAX_SAMPLES_PER_SERVICE,
  recordDuration,
  removeSample,
  sanitizeDisplayName,
  type ServiceStats,
} from '../src/domain';

const corte = { id: 'corte', defaultDurationMin: 30 };

describe('sanitizeDisplayName', () => {
  it('gera rótulo público com primeiro nome e inicial do último sobrenome', () => {
    assert.deepEqual(sanitizeDisplayName('  lucas   martins  silva '), {
      displayName: 'lucas martins silva',
      label: 'lucas S.',
    });
    assert.equal(sanitizeDisplayName('João').label, 'João');
    assert.equal(sanitizeDisplayName("Maria D'Ávila").label, 'Maria D.');
  });

  it('aceita acentos e hífen', () => {
    assert.equal(sanitizeDisplayName('Ana-Luíza Conceição').displayName, 'Ana-Luíza Conceição');
  });

  for (const invalid of ['A', ' ', '', '123', 'Zé 2', 'http://spam.com', 'Lucas 😎', '-Lucas', 'x'.repeat(31), 42, null]) {
    it(`rejeita ${JSON.stringify(invalid)}`, () => {
      assert.throws(
        () => sanitizeDisplayName(invalid),
        (e: unknown) => e instanceof DomainError && e.code === 'invalid-name',
      );
    });
  }
});

describe('estatísticas de duração', () => {
  it('usa a duração padrão até ter 3 amostras', () => {
    let stats: ServiceStats = {};
    stats = recordDuration(stats, corte, { ticketId: 'a', minutes: 20 });
    stats = recordDuration(stats, corte, { ticketId: 'b', minutes: 22 });
    assert.equal(expectedDurationMin(stats, corte), 30);
    stats = recordDuration(stats, corte, { ticketId: 'c', minutes: 24 });
    assert.equal(expectedDurationMin(stats, corte), 22);
  });

  it('usa a mediana (robusta a outliers) e média dos centrais quando par', () => {
    let stats: ServiceStats = {};
    for (const [id, minutes] of [['a', 20], ['b', 22], ['c', 25], ['d', 100]] as const) {
      stats = recordDuration(stats, corte, { ticketId: id, minutes });
    }
    assert.equal(expectedDurationMin(stats, corte), 23.5);
  });

  it('ignora durações absurdas', () => {
    let stats: ServiceStats = {};
    stats = recordDuration(stats, corte, { ticketId: 'curto', minutes: 1 });
    stats = recordDuration(stats, corte, { ticketId: 'esqueceu', minutes: 30 * 4 + 1 });
    assert.deepEqual(stats, {});
  });

  it('mantém só as últimas amostras e não duplica o mesmo ticket', () => {
    let stats: ServiceStats = {};
    for (let i = 0; i < MAX_SAMPLES_PER_SERVICE + 5; i++) {
      stats = recordDuration(stats, corte, { ticketId: `t${i}`, minutes: 20 + (i % 3) });
    }
    stats = recordDuration(stats, corte, { ticketId: 't24', minutes: 40 });
    const samples = stats.corte ?? [];
    assert.equal(samples.length, MAX_SAMPLES_PER_SERVICE);
    assert.equal(samples.filter((s) => s.ticketId === 't24').length, 1);
    assert.equal(samples.at(-1)?.minutes, 40);
  });

  it('remove a amostra de um ticket', () => {
    const stats = recordDuration({}, corte, { ticketId: 'a', minutes: 20 });
    assert.deepEqual(removeSample(stats, 'corte', 'a'), { corte: [] });
    assert.equal(removeSample(stats, 'corte', 'inexistente'), stats);
  });
});

describe('consumeRateLimit', () => {
  const policy = { max: 2, windowMs: 1000 };

  it('permite até o limite dentro da janela e informa quando tentar de novo', () => {
    const first = consumeRateLimit([], 0, policy);
    const second = consumeRateLimit(first.history, 100, policy);
    const third = consumeRateLimit(second.history, 200, policy);
    assert.equal(first.allowed, true);
    assert.equal(second.allowed, true);
    assert.equal(third.allowed, false);
    assert.equal(third.retryAfterMs, 800);
  });

  it('libera quando as tentativas antigas saem da janela', () => {
    const decision = consumeRateLimit([0, 100], 1001, policy);
    assert.equal(decision.allowed, true);
    assert.deepEqual(decision.history, [100, 1001]);
  });
});
