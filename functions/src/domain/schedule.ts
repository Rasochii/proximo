import { DomainError } from './errors';
import { parseHHmm } from './time';
import { WEEKDAYS, type TimeInterval, type WeekdayKey, type WeeklySchedule } from './types';

/** Intervalo em minutos desde a meia-noite local: [start, end). */
export interface MinuteInterval {
  readonly start: number;
  readonly end: number;
}

const MAX_INTERVALS_PER_DAY = 6;

/**
 * Valida e normaliza (ordena) um horário semanal vindo de fora do domínio.
 * Regras: "HH:mm" válidos, início < fim, sem sobreposição, até 6 períodos por dia.
 */
export function parseWeeklySchedule(input: unknown): WeeklySchedule {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    throw new DomainError('invalid-schedule');
  }
  const source = input as Record<string, unknown>;
  const result = {} as Record<WeekdayKey, readonly TimeInterval[]>;

  for (const day of WEEKDAYS) {
    const raw = source[day] ?? [];
    if (!Array.isArray(raw) || raw.length > MAX_INTERVALS_PER_DAY) {
      throw new DomainError('invalid-schedule', undefined, { day });
    }
    const parsed = raw.map((item: unknown) => parseInterval(item, day));
    parsed.sort((a, b) => a.minutes.start - b.minutes.start);
    for (let i = 1; i < parsed.length; i++) {
      const previous = parsed[i - 1]!;
      const current = parsed[i]!;
      if (current.minutes.start < previous.minutes.end) {
        throw new DomainError('invalid-schedule', 'Os períodos não podem se sobrepor.', { day });
      }
    }
    result[day] = parsed.map((p) => p.interval);
  }
  return result;
}

function parseInterval(item: unknown, day: WeekdayKey): { interval: TimeInterval; minutes: MinuteInterval } {
  if (typeof item !== 'object' || item === null) {
    throw new DomainError('invalid-schedule', undefined, { day });
  }
  const { start, end } = item as Record<string, unknown>;
  if (typeof start !== 'string' || typeof end !== 'string') {
    throw new DomainError('invalid-schedule', undefined, { day });
  }
  const startMin = start === '24:00' ? null : parseHHmm(start);
  const endMin = parseHHmm(end);
  if (startMin === null || endMin === null || startMin >= endMin) {
    throw new DomainError('invalid-schedule', 'Cada período precisa ter início antes do fim.', { day });
  }
  return { interval: { start, end }, minutes: { start: startMin, end: endMin } };
}

/** Períodos do dia em minutos, ordenados. Assume horário já validado. */
export function intervalsFor(schedule: WeeklySchedule, weekday: WeekdayKey): MinuteInterval[] {
  return schedule[weekday]
    .map((interval) => ({ start: parseHHmm(interval.start) ?? 0, end: parseHHmm(interval.end) ?? 0 }))
    .filter((interval) => interval.start < interval.end)
    .sort((a, b) => a.start - b.start);
}

/** Primeira abertura e último fechamento do dia, ou null se fechado. */
export function dayBounds(intervals: readonly MinuteInterval[]): MinuteInterval | null {
  const first = intervals[0];
  const last = intervals[intervals.length - 1];
  if (!first || !last) return null;
  return { start: first.start, end: last.end };
}

/**
 * Leva um instante para o próximo momento de funcionamento:
 * dentro de um período → ele mesmo; num intervalo (almoço) ou antes de abrir → próxima abertura;
 * depois do último fechamento → null.
 */
export function alignToOpen(intervals: readonly MinuteInterval[], minute: number): number | null {
  for (const interval of intervals) {
    if (minute < interval.start) return interval.start;
    if (minute < interval.end) return minute;
  }
  return null;
}
