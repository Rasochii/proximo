import type { DurationSample, Service, ServiceStats } from './types';

export const MAX_SAMPLES_PER_SERVICE = 20;
export const MIN_SAMPLES_FOR_MEDIAN = 3;
/** Atendimentos mais curtos que isso não são considerados (ex.: chamado e liberado por engano). */
export const MIN_VALID_DURATION_MIN = 2;
/** Atendimentos maiores que N× a duração padrão são considerados outliers (barbeiro esqueceu de apertar). */
export const MAX_DURATION_FACTOR = 4;

/**
 * Registra a duração real de um atendimento, mantendo apenas as últimas amostras.
 * Ignora durações absurdas para não contaminar o ETA.
 */
export function recordDuration(
  stats: ServiceStats,
  service: Pick<Service, 'id' | 'defaultDurationMin'>,
  sample: DurationSample,
): ServiceStats {
  if (sample.minutes < MIN_VALID_DURATION_MIN || sample.minutes > service.defaultDurationMin * MAX_DURATION_FACTOR) {
    return stats;
  }
  const current = (stats[service.id] ?? []).filter((s) => s.ticketId !== sample.ticketId);
  const next = [...current, { ticketId: sample.ticketId, minutes: round1(sample.minutes) }].slice(-MAX_SAMPLES_PER_SERVICE);
  return { ...stats, [service.id]: next };
}

/** Remove a amostra de um ticket (usado ao desfazer um atendimento). */
export function removeSample(stats: ServiceStats, serviceId: string, ticketId: string): ServiceStats {
  const current = stats[serviceId];
  if (!current?.some((s) => s.ticketId === ticketId)) return stats;
  return { ...stats, [serviceId]: current.filter((s) => s.ticketId !== ticketId) };
}

/** Duração esperada: mediana das últimas amostras (robusta a outliers) ou a duração padrão do serviço. */
export function expectedDurationMin(
  stats: ServiceStats,
  service: Pick<Service, 'id' | 'defaultDurationMin'>,
): number {
  const samples = stats[service.id] ?? [];
  if (samples.length < MIN_SAMPLES_FOR_MEDIAN) return service.defaultDurationMin;
  return round1(median(samples.map((s) => s.minutes)));
}

function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[middle - 1]! + sorted[middle]!) / 2 : sorted[middle]!;
}

function round1(value: number): number {
  return Math.round(value * 10) / 10;
}
