export interface RateLimitPolicy {
  readonly max: number;
  readonly windowMs: number;
}

export interface RateLimitDecision {
  readonly allowed: boolean;
  /** Histórico atualizado (apenas tentativas dentro da janela). */
  readonly history: readonly number[];
  readonly retryAfterMs: number;
}

/** Política padrão para entrar na fila: 5 entradas a cada 10 minutos por usuário. */
export const JOIN_RATE_LIMIT: RateLimitPolicy = { max: 5, windowMs: 10 * 60 * 1000 };

/** Janela deslizante: consome uma tentativa se houver espaço. Função pura. */
export function consumeRateLimit(history: readonly number[], nowMs: number, policy: RateLimitPolicy): RateLimitDecision {
  const windowStart = nowMs - policy.windowMs;
  const recent = history.filter((t) => t > windowStart && t <= nowMs).sort((a, b) => a - b);

  if (recent.length >= policy.max) {
    const oldest = recent[0]!;
    return { allowed: false, history: recent, retryAfterMs: Math.max(0, oldest + policy.windowMs - nowMs) };
  }
  return { allowed: true, history: [...recent, nowMs], retryAfterMs: 0 };
}
