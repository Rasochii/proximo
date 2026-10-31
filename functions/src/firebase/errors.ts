import { logger } from 'firebase-functions';
import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

import { isDomainError, type DomainErrorCode } from '../domain';

const HTTPS_CODE_BY_DOMAIN_CODE: Partial<Record<DomainErrorCode, FunctionsErrorCode>> = {
  'invalid-argument': 'invalid-argument',
  'invalid-name': 'invalid-argument',
  'invalid-service': 'invalid-argument',
  'invalid-schedule': 'invalid-argument',
  'ticket-not-found': 'not-found',
  'barber-not-found': 'not-found',
  'not-ticket-owner': 'permission-denied',
  'queue-full': 'resource-exhausted',
  'rate-limited': 'resource-exhausted',
  'request-conflict': 'already-exists',
  'serving-changed': 'aborted',
  'undo-conflict': 'aborted',
  'day-mismatch': 'internal',
};

/**
 * Converte qualquer erro em `HttpsError`. Erros de domínio levam o `code` estável em `details`
 * (o app traduz por i18n); erros inesperados são logados sem dados pessoais e viram `internal`.
 */
export function toHttpsError(error: unknown, context: { readonly fn: string }): HttpsError {
  if (error instanceof HttpsError) return error;
  if (isDomainError(error)) {
    const httpsCode = HTTPS_CODE_BY_DOMAIN_CODE[error.code] ?? 'failed-precondition';
    if (httpsCode === 'internal') logger.error('Domain invariant violated', { fn: context.fn, code: error.code });
    return new HttpsError(httpsCode, error.message, { code: error.code, ...error.details });
  }
  logger.error('Unexpected error', { fn: context.fn, error: error instanceof Error ? error.message : String(error) });
  return new HttpsError('internal', 'Erro inesperado. Tente novamente.');
}
