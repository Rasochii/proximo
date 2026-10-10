import type { DocumentReference } from 'firebase-admin/firestore';

import { db } from './app';

/** Caminhos do Firestore em um único lugar (espelhados em `firestore.rules`). */
export const refs = {
  shop: (shopId: string): DocumentReference => db().doc(`shops/${shopId}`),
  member: (shopId: string, uid: string): DocumentReference => db().doc(`shops/${shopId}/members/${uid}`),
  day: (shopId: string, dateKey: string): DocumentReference => db().doc(`shops/${shopId}/days/${dateKey}`),
  stats: (shopId: string): DocumentReference => db().doc(`shops/${shopId}/private/stats`),
  publicQueue: (shopId: string): DocumentReference => db().doc(`publicQueues/${shopId}`),
  activeTicket: (uid: string): DocumentReference => db().doc(`activeTickets/${uid}`),
  rateLimit: (uid: string): DocumentReference => db().doc(`rateLimits/${uid}`),
  /** Gera um id aleatório de documento (usado como id do ticket). */
  newId: (): string => db().collection('_ids').doc().id,
};
