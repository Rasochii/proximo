import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { DEFAULT_SHOP_SETTINGS, DomainError, parseShop } from '../src/domain';

const valid = {
  name: ' Barbearia do Zé ',
  slug: 'barbearia-do-ze',
  timezone: 'America/Sao_Paulo',
  schedule: { mon: [{ start: '09:00', end: '18:00' }] },
  services: [{ id: 'corte', name: 'Corte', defaultDurationMin: 30 }],
};

function invalid(data: unknown): void {
  assert.throws(() => parseShop('s1', data), (e: unknown) => e instanceof DomainError);
}

describe('parseShop', () => {
  it('normaliza dados e aplica configurações padrão', () => {
    const shop = parseShop('s1', valid);
    assert.equal(shop.name, 'Barbearia do Zé');
    assert.deepEqual(shop.settings, DEFAULT_SHOP_SETTINGS);
    assert.deepEqual(shop.services, [{ id: 'corte', name: 'Corte', defaultDurationMin: 30, active: true }]);
    assert.deepEqual(shop.schedule.sun, []);
  });

  it('usa São Paulo como fuso padrão e aceita configurações válidas', () => {
    const { timezone, ...withoutTz } = valid;
    const shop = parseShop('s1', { ...withoutTz, settings: { maxTicketsPerDay: 50 } });
    assert.equal(shop.timezone, timezone);
    assert.equal(shop.settings.maxTicketsPerDay, 50);
  });

  it('rejeita dados inválidos', () => {
    invalid(null);
    invalid({ ...valid, name: 'Z' });
    invalid({ ...valid, slug: 'Com Espaço' });
    invalid({ ...valid, slug: '-ze' });
    invalid({ ...valid, timezone: 'Lugar/Nenhum' });
    invalid({ ...valid, services: [] });
    invalid({ ...valid, services: [{ id: 'corte', name: 'Corte', defaultDurationMin: 2 }] });
    invalid({ ...valid, services: [{ id: 'a b', name: 'Corte', defaultDurationMin: 30 }] });
    invalid({ ...valid, services: [valid.services[0], valid.services[0]] });
    invalid({ ...valid, settings: { maxTicketsPerDay: 1000 } });
    invalid({ ...valid, settings: { undoWindowSec: 1.5 } });
    invalid({ ...valid, schedule: { mon: [{ start: '18:00', end: '09:00' }] } });
  });
});
