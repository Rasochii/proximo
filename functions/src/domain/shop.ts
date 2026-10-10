import { DomainError } from './errors';
import { parseWeeklySchedule } from './schedule';
import { isValidTimeZone } from './time';
import { DEFAULT_SHOP_SETTINGS, type Service, type Shop, type ShopSettings } from './types';

const SLUG = /^[a-z0-9](?:[a-z0-9-]{1,46}[a-z0-9])$/;
const SERVICE_ID = /^[A-Za-z0-9_-]{1,64}$/;
const MAX_SERVICES = 30;

/**
 * Converte e valida um documento de barbearia vindo do banco ou do app.
 * Configurações ausentes recebem os valores padrão; valores fora de faixa são recusados.
 */
export function parseShop(id: string, data: unknown): Shop {
  if (typeof data !== 'object' || data === null) throw new DomainError('invalid-argument', 'Barbearia inválida.');
  const raw = data as Record<string, unknown>;

  const name = typeof raw.name === 'string' ? raw.name.trim() : '';
  if (name.length < 2 || name.length > 60) throw new DomainError('invalid-argument', 'Nome da barbearia inválido.');

  const slug = raw.slug;
  if (typeof slug !== 'string' || !SLUG.test(slug)) throw new DomainError('invalid-argument', 'Slug inválido.');

  const timezone = raw.timezone ?? 'America/Sao_Paulo';
  if (typeof timezone !== 'string' || !isValidTimeZone(timezone)) {
    throw new DomainError('invalid-argument', 'Fuso horário inválido.');
  }

  return {
    id,
    name,
    slug,
    timezone,
    schedule: parseWeeklySchedule(raw.schedule),
    services: parseServices(raw.services),
    settings: parseSettings(raw.settings),
  };
}

function parseServices(input: unknown): Service[] {
  if (!Array.isArray(input) || input.length === 0 || input.length > MAX_SERVICES) {
    throw new DomainError('invalid-argument', 'Cadastre de 1 a 30 serviços.');
  }
  const ids = new Set<string>();
  return input.map((item: unknown) => {
    const s = (typeof item === 'object' && item !== null ? item : {}) as Record<string, unknown>;
    const id = s.id;
    const name = typeof s.name === 'string' ? s.name.trim() : '';
    const duration = s.defaultDurationMin;
    if (
      typeof id !== 'string' ||
      !SERVICE_ID.test(id) ||
      ids.has(id) ||
      name.length < 2 ||
      name.length > 40 ||
      !isIntegerIn(duration, 5, 240)
    ) {
      throw new DomainError('invalid-argument', 'Serviço inválido.', { serviceId: typeof id === 'string' ? id : null });
    }
    ids.add(id);
    return { id, name, defaultDurationMin: duration, active: s.active !== false };
  });
}

function parseSettings(input: unknown): ShopSettings {
  const s = (typeof input === 'object' && input !== null ? input : {}) as Record<string, unknown>;
  const pick = (key: keyof ShopSettings, min: number, max: number): number => {
    const value = s[key] ?? DEFAULT_SHOP_SETTINGS[key];
    if (!isIntegerIn(value, min, max)) throw new DomainError('invalid-argument', `Configuração inválida: ${key}.`);
    return value;
  };
  return {
    closeEntryMinutesBefore: pick('closeEntryMinutesBefore', 0, 240),
    openEntryMinutesBefore: pick('openEntryMinutesBefore', 0, 240),
    maxTicketsPerDay: pick('maxTicketsPerDay', 1, 300),
    undoWindowSec: pick('undoWindowSec', 5, 60),
  };
}

function isIntegerIn(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= min && value <= max;
}
