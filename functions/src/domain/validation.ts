import { DomainError } from './errors';
import { BARBER_STATUSES, TICKET_SOURCES, type BarberStatus, type FinishOutcome, type TicketSource } from './types';

/**
 * Validação das entradas das callables. Tudo que vem do cliente é `unknown` até passar por aqui.
 * Escrito sem bibliotecas para manter o domínio sem dependências.
 */

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SAFE_ID = /^[A-Za-z0-9_-]{1,64}$/;

type Payload = Record<string, unknown>;

function asPayload(data: unknown): Payload {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new DomainError('invalid-argument');
  }
  return data as Payload;
}

function requestId(payload: Payload): string {
  const value = payload.requestId;
  if (typeof value !== 'string' || !UUID_V4.test(value)) {
    throw new DomainError('invalid-argument', 'requestId deve ser um UUID v4.', { field: 'requestId' });
  }
  return value.toLowerCase();
}

function id(payload: Payload, field: string): string {
  const value = payload[field];
  if (typeof value !== 'string' || !SAFE_ID.test(value)) {
    throw new DomainError('invalid-argument', undefined, { field });
  }
  return value;
}

function optionalId(payload: Payload, field: string): string | null {
  return payload[field] === undefined || payload[field] === null ? null : id(payload, field);
}

function oneOf<T extends string>(payload: Payload, field: string, allowed: readonly T[], fallback?: T): T {
  const value = payload[field] ?? fallback;
  if (typeof value !== 'string' || !(allowed as readonly string[]).includes(value)) {
    throw new DomainError('invalid-argument', undefined, { field });
  }
  return value as T;
}

function bool(payload: Payload, field: string): boolean {
  const value = payload[field];
  if (typeof value !== 'boolean') throw new DomainError('invalid-argument', undefined, { field });
  return value;
}

export interface JoinQueueInput {
  readonly requestId: string;
  readonly shopId: string;
  readonly name: unknown;
  readonly serviceId: string;
  readonly source: TicketSource;
  readonly preferredBarberId: string | null;
}

export function parseJoinQueueInput(data: unknown): JoinQueueInput {
  const p = asPayload(data);
  return {
    requestId: requestId(p),
    shopId: id(p, 'shopId'),
    name: p.name, // validado pelo domínio (sanitizeDisplayName)
    serviceId: id(p, 'serviceId'),
    source: oneOf(p, 'source', TICKET_SOURCES, 'link'),
    preferredBarberId: optionalId(p, 'preferredBarberId'),
  };
}

export interface TicketInput {
  readonly requestId: string;
  readonly shopId: string;
  readonly ticketId: string;
}

export function parseTicketInput(data: unknown): TicketInput {
  const p = asPayload(data);
  return { requestId: requestId(p), shopId: id(p, 'shopId'), ticketId: id(p, 'ticketId') };
}

const FINISH_OUTCOMES: readonly FinishOutcome[] = ['done', 'no_show'];

export interface AdvanceInput {
  readonly requestId: string;
  readonly shopId: string;
  readonly outcome: FinishOutcome;
}

export function parseAdvanceInput(data: unknown): AdvanceInput {
  const p = asPayload(data);
  return { requestId: requestId(p), shopId: id(p, 'shopId'), outcome: oneOf(p, 'outcome', FINISH_OUTCOMES, 'done') };
}

export interface ShopActionInput {
  readonly requestId: string;
  readonly shopId: string;
}

export function parseShopActionInput(data: unknown): ShopActionInput {
  const p = asPayload(data);
  return { requestId: requestId(p), shopId: id(p, 'shopId') };
}

export interface BarberStatusInput extends ShopActionInput {
  readonly status: BarberStatus;
}

export function parseBarberStatusInput(data: unknown): BarberStatusInput {
  const p = asPayload(data);
  return { requestId: requestId(p), shopId: id(p, 'shopId'), status: oneOf(p, 'status', BARBER_STATUSES) };
}

export interface AcceptingEntriesInput extends ShopActionInput {
  readonly accepting: boolean;
}

export function parseAcceptingEntriesInput(data: unknown): AcceptingEntriesInput {
  const p = asPayload(data);
  return { requestId: requestId(p), shopId: id(p, 'shopId'), accepting: bool(p, 'accepting') };
}
