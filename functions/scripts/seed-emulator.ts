/**
 * Popula os emuladores com uma barbearia de demonstração.
 *
 * Uso (com `npm run serve` rodando em outro terminal):
 *   npm run seed
 *
 * Só funciona contra emuladores: o script se recusa a rodar sem as variáveis *_EMULATOR_HOST.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { buildPublicQueue, createQueueDay, currentDateKey, parseShop } from '../src/domain';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

const PROJECT_ID = 'demo-proximo';
const SHOP_ID = 'barbearia-do-ze';

/** Credenciais fictícias, válidas apenas no emulador local. */
export const DEMO_BARBERS = [
  { uid: 'barbeiro-ze', email: 'ze@proximo.dev', displayName: 'Zé', role: 'owner' },
  { uid: 'barbeiro-joao', email: 'joao@proximo.dev', displayName: 'João', role: 'barber' },
] as const;
const DEMO_PASSWORD = 'proximo123';

async function main(): Promise<void> {
  if (!PROJECT_ID.startsWith('demo-')) throw new Error('Seed permitido apenas em projetos demo-*.');

  initializeApp({ projectId: PROJECT_ID });
  const db = getFirestore();
  const auth = getAuth();

  const workday = [
    { start: '09:00', end: '12:00' },
    { start: '13:00', end: '19:00' },
  ];

  const shopData = {
    name: 'Barbearia do Zé',
    slug: SHOP_ID,
    timezone: 'America/Sao_Paulo',
    schedule: {
      sun: [],
      mon: workday,
      tue: workday,
      wed: workday,
      thu: workday,
      fri: workday,
      sat: [{ start: '08:00', end: '14:00' }],
    },
    services: [
      { id: 'corte', name: 'Corte', defaultDurationMin: 30, active: true },
      { id: 'barba', name: 'Barba', defaultDurationMin: 20, active: true },
      { id: 'combo', name: 'Corte + Barba', defaultDurationMin: 45, active: true },
    ],
    settings: { closeEntryMinutesBefore: 15, openEntryMinutesBefore: 30, maxTicketsPerDay: 200, undoWindowSec: 15 },
    ownerUid: DEMO_BARBERS[0].uid,
    createdAt: Date.now(),
  };
  await db.doc(`shops/${SHOP_ID}`).set(shopData);

  for (const barber of DEMO_BARBERS) {
    try {
      await auth.createUser({ uid: barber.uid, email: barber.email, password: DEMO_PASSWORD, displayName: barber.displayName });
    } catch (error) {
      if ((error as { code?: string }).code !== 'auth/uid-already-exists') throw error;
    }
    await db.doc(`shops/${SHOP_ID}/members/${barber.uid}`).set({
      role: barber.role,
      displayName: barber.displayName,
      active: true,
      joinedAt: Date.now(),
    });
  }

  // Projeção pública da fila vazia de hoje, para a rota /b/:slug já mostrar a fila antes do primeiro comando.
  // Se o dia já existe, as callables mantêm a projeção e o seed não a sobrescreve.
  const nowMs = Date.now();
  const shop = parseShop(SHOP_ID, shopData);
  const dateKey = currentDateKey(shop, nowMs);
  const daySnap = await db.doc(`shops/${SHOP_ID}/days/${dateKey}`).get();
  if (!daySnap.exists) {
    const emptyDay = createQueueDay(SHOP_ID, dateKey, nowMs);
    await db.doc(`publicQueues/${SHOP_ID}`).set(buildPublicQueue(emptyDay, { nowMs, shop, stats: {} }));
  }

  console.log(`✔ Barbearia "${SHOP_ID}" criada.`);
  console.log(`✔ Barbeiros: ${DEMO_BARBERS.map((b) => b.email).join(', ')} (senha: ${DEMO_PASSWORD})`);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
