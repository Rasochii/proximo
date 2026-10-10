import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

/** Região das functions (ADR: São Paulo, menor latência para o público-alvo). */
export const REGION = 'southamerica-east1';

/**
 * App Check só é exigido quando `APP_CHECK_ENFORCED=true` (arquivo `functions/.env.<projeto>`).
 * Nos emuladores e no início do projeto fica em modo de monitoramento.
 */
export const APP_CHECK_ENFORCED = process.env.APP_CHECK_ENFORCED === 'true';

let firestore: Firestore | undefined;

export function db(): Firestore {
  if (!firestore) {
    if (getApps().length === 0) initializeApp();
    firestore = getFirestore();
    firestore.settings({ ignoreUndefinedProperties: true });
  }
  return firestore;
}
