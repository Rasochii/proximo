import { WEEKDAYS, type WeekdayKey } from './types';

/** Data/hora "de parede" no fuso da barbearia. */
export interface LocalDateTime {
  /** 'YYYY-MM-DD' */
  readonly dateKey: string;
  readonly weekday: WeekdayKey;
  /** Minutos desde a meia-noite local, com fração de segundos. */
  readonly minuteOfDay: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let formatter = formatters.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      weekday: 'short',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    });
    formatters.set(timeZone, formatter);
  }
  return formatter;
}

export function isValidTimeZone(timeZone: string): boolean {
  try {
    formatterFor(timeZone);
    return true;
  } catch {
    return false;
  }
}

const SHORT_WEEKDAYS: Readonly<Record<string, WeekdayKey>> = {
  Sun: 'sun',
  Mon: 'mon',
  Tue: 'tue',
  Wed: 'wed',
  Thu: 'thu',
  Fri: 'fri',
  Sat: 'sat',
};

/** Converte um instante para data/hora local no fuso informado (respeita horário de verão). */
export function toLocal(epochMs: number, timeZone: string): LocalDateTime {
  const parts: Record<string, string> = {};
  for (const part of formatterFor(timeZone).formatToParts(new Date(epochMs))) {
    parts[part.type] = part.value;
  }
  const weekday = SHORT_WEEKDAYS[parts.weekday ?? ''];
  if (!weekday) {
    throw new Error(`Unexpected weekday from Intl: ${parts.weekday}`);
  }
  // Alguns motores ainda devolvem "24" à meia-noite; normaliza para 0.
  const hour = Number(parts.hour) % 24;
  const minute = Number(parts.minute);
  const second = Number(parts.second);
  return {
    dateKey: `${parts.year}-${parts.month}-${parts.day}`,
    weekday,
    minuteOfDay: hour * 60 + minute + second / 60,
  };
}

const HOUR_MS = 60 * 60 * 1000;

/**
 * Instante (epoch ms) em que termina o dia local de `epochMs`: o primeiro milissegundo do dia
 * seguinte no fuso informado.
 *
 * Procura a virada por busca binária em vez de somar 24 h, porque nos dias de troca de horário de
 * verão o dia tem 23 ou 25 horas (e em alguns fusos a meia-noite nem existe).
 *
 * Pressupõe que o dia local não passa de 26 h e que a data não volta atrás nesse intervalo, o que
 * vale para as regras de fuso atuais.
 */
export function endOfLocalDayMs(epochMs: number, timeZone: string): number {
  const today = toLocal(epochMs, timeZone).dateKey;
  let stillToday = epochMs;
  let alreadyLater = epochMs + 26 * HOUR_MS; // um dia local nunca passa de 25 h
  while (alreadyLater - stillToday > 1) {
    const middle = stillToday + Math.floor((alreadyLater - stillToday) / 2);
    if (toLocal(middle, timeZone).dateKey === today) stillToday = middle;
    else alreadyLater = middle;
  }
  return alreadyLater;
}

const HH_MM = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** "HH:mm" → minutos desde a meia-noite; aceita "24:00" como fim do dia. Retorna null se inválido. */
export function parseHHmm(value: string): number | null {
  if (value === '24:00') return 24 * 60;
  const match = HH_MM.exec(value);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

export function weekdayIndex(weekday: WeekdayKey): number {
  return WEEKDAYS.indexOf(weekday);
}
