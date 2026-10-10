import type { DocumentSnapshot, Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import {
  buildPublicQueue,
  consumeRateLimit,
  createQueueDay,
  currentDateKey,
  DomainError,
  parseShop,
  type ActiveTicketRef,
  type CommandOutcome,
  type DayContext,
  type Effect,
  type QueueDay,
  type RateLimitPolicy,
  type ServiceStats,
} from '../domain';
import { db } from './app';
import { refs } from './refs';

/** Versão do formato persistido do agregado (para migrações futuras). */
const DAY_SCHEMA_VERSION = 1;

/** Picos de entradas simultâneas (ex.: QR Code na porta) disputam o mesmo documento; damos mais tentativas. */
const TRANSACTION_OPTIONS = { maxAttempts: 10 } as const;

export interface Member {
  readonly uid: string;
  readonly role: 'owner' | 'barber';
  readonly displayName: string;
}

export interface CommandInput {
  readonly day: QueueDay;
  readonly ctx: DayContext;
  readonly member: Member | null;
  readonly activeTicket: ActiveTicketRef | null;
}

export interface QueueCommandSpec<R> {
  readonly shopId: string;
  /** Usado para não consumir rate limit em retries de uma requisição já processada. */
  readonly requestId: string;
  readonly actorUid: string;
  /** Exige que o ator seja membro ativo da barbearia (barbeiro ou dono). */
  readonly requireMember: boolean;
  /** Lê `activeTickets/{actorUid}` antes de executar (necessário para entrar na fila). */
  readonly loadActiveTicket?: boolean;
  readonly rateLimit?: { readonly key: string; readonly policy: RateLimitPolicy };
  readonly execute: (input: CommandInput) => CommandOutcome<R>;
}

/**
 * Executa um comando do domínio dentro de UMA transação do Firestore (ADR 0003/0004):
 * 1. lê barbearia, agregado do dia, estatísticas e documentos auxiliares;
 * 2. roda a regra pura do domínio;
 * 3. lê o necessário para aplicar os efeitos (sempre antes da primeira escrita);
 * 4. grava agregado, estatísticas, projeção pública e efeitos de forma atômica.
 *
 * O SDK de servidor usa locks pessimistas, então comandos concorrentes na mesma fila são serializados.
 */
export async function runQueueCommand<R>(spec: QueueCommandSpec<R>): Promise<R> {
  return db().runTransaction(async (tx) => {
    const nowMs = Date.now();

    const shopSnap = await tx.get(refs.shop(spec.shopId));
    if (!shopSnap.exists) throw new HttpsError('not-found', 'Barbearia não encontrada.');
    const shop = parseShop(shopSnap.id, shopSnap.data());
    const dateKey = currentDateKey(shop, nowMs);

    const dayRef = refs.day(shop.id, dateKey);
    const statsRef = refs.stats(shop.id);
    const memberRef = spec.requireMember ? refs.member(shop.id, spec.actorUid) : null;
    const activeRef = spec.loadActiveTicket ? refs.activeTicket(spec.actorUid) : null;
    const rateRef = spec.rateLimit ? refs.rateLimit(spec.actorUid) : null;

    const [daySnap, statsSnap, memberSnap, activeSnap, rateSnap] = await Promise.all([
      tx.get(dayRef),
      tx.get(statsRef),
      memberRef ? tx.get(memberRef) : Promise.resolve(null),
      activeRef ? tx.get(activeRef) : Promise.resolve(null),
      rateRef ? tx.get(rateRef) : Promise.resolve(null),
    ]);

    const member = memberSnap ? toMember(memberSnap) : null;
    if (spec.requireMember && !member) {
      throw new HttpsError('permission-denied', 'Você não faz parte da equipe desta barbearia.');
    }

    const day = daySnap.exists ? fromDayDoc(daySnap) : createQueueDay(shop.id, dateKey, nowMs);
    const isRetry = day.processed.some((p) => p.requestId === spec.requestId);

    let rateHistory: readonly number[] | null = null;
    if (spec.rateLimit && rateSnap && !isRetry) {
      const stored = rateSnap.get(spec.rateLimit.key) as unknown;
      const decision = consumeRateLimit(Array.isArray(stored) ? stored.filter(isNumber) : [], nowMs, spec.rateLimit.policy);
      if (!decision.allowed) throw new DomainError('rate-limited', undefined, { retryAfterMs: decision.retryAfterMs });
      rateHistory = decision.history;
    }

    const stats = (statsSnap.get('services') ?? {}) as ServiceStats;
    const ctx: DayContext = { nowMs, shop, stats };

    const outcome = spec.execute({
      day,
      ctx,
      member,
      activeTicket: activeSnap?.exists ? (activeSnap.data() as ActiveTicketRef) : null,
    });
    if (outcome.replayed) return outcome.result;

    // Leituras para aplicar os efeitos — precisam acontecer antes de qualquer escrita.
    const effectSnaps = await Promise.all(outcome.effects.map((effect) => tx.get(refs.activeTicket(effect.uid))));

    tx.set(dayRef, { ...outcome.day, schemaVersion: DAY_SCHEMA_VERSION });
    if (outcome.stats !== stats) tx.set(statsRef, { services: outcome.stats, updatedAt: nowMs });
    tx.set(refs.publicQueue(shop.id), buildPublicQueue(outcome.day, { ...ctx, stats: outcome.stats }));
    outcome.effects.forEach((effect, index) => applyEffect(tx, effect, effectSnaps[index]!, nowMs));
    if (rateRef && rateHistory && spec.rateLimit) {
      tx.set(rateRef, { [spec.rateLimit.key]: rateHistory, updatedAt: nowMs }, { merge: true });
    }

    return outcome.result;
  }, TRANSACTION_OPTIONS);
}


function applyEffect(tx: Transaction, effect: Effect, current: DocumentSnapshot, nowMs: number): void {
  const ref = refs.activeTicket(effect.uid);
  switch (effect.type) {
    case 'activeTicket.set':
      if (effect.onlyIfAbsent && current.exists) return;
      tx.set(ref, { ...effect.ref, updatedAt: nowMs });
      return;
    case 'activeTicket.clear':
      // Só apaga se ainda apontar para este ticket (o usuário pode já estar em outra fila).
      if (current.exists && current.get('ticketId') === effect.ticketId) tx.delete(ref);
      return;
  }
}

function toMember(snap: DocumentSnapshot): Member | null {
  if (!snap.exists || snap.get('active') !== true) return null;
  const role = snap.get('role') as unknown;
  if (role !== 'owner' && role !== 'barber') return null;
  const displayName = snap.get('displayName') as unknown;
  return { uid: snap.id, role, displayName: typeof displayName === 'string' ? displayName : 'Barbeiro' };
}

function fromDayDoc(snap: DocumentSnapshot): QueueDay {
  const { schemaVersion: _schemaVersion, ...day } = snap.data() as QueueDay & { schemaVersion?: number };
  return day;
}

function isNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}
