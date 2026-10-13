/**
 * Popula os emuladores com uma barbearia de demonstração, aberta o dia todo e com clientes já na
 * fila, para dar para testar o app a qualquer hora.
 *
 * Uso (com `npm run serve` rodando em outro terminal):
 *   npm run seed
 *
 * Feito para os emuladores: o projeto é fixo (`demo-proximo`) e, sem as variáveis `*_EMULATOR_HOST`
 * no ambiente, os hosts são os da máquina local.
 */
import { randomUUID } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

import {
  buildPublicQueue,
  createQueueDay,
  currentDateKey,
  joinQueue,
  parseShop,
} from '../src/domain';
import { db, REGION } from '../src/firebase/app';
import { runQueueCommand } from '../src/firebase/queueRepository';
import { refs } from '../src/firebase/refs';
import * as callables from '../src/index';

// `||=` e não `??=`: uma variável vazia desligaria o modo emulador do Admin SDK.
process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST ||= '127.0.0.1:9099';
const FUNCTIONS_EMULATOR_HOST = process.env.FUNCTIONS_EMULATOR_HOST || '127.0.0.1:5001';

const PROJECT_ID = 'demo-proximo';
const SHOP_ID = 'barbearia-do-ze';

/** Credenciais fictícias, válidas apenas no emulador local. */
export const DEMO_BARBERS = [
  { uid: 'barbeiro-ze', email: 'ze@proximo.dev', displayName: 'Zé', role: 'owner' },
  { uid: 'barbeiro-joao', email: 'joao@proximo.dev', displayName: 'João', role: 'barber' },
] as const;
const DEMO_PASSWORD = 'proximo123';

/** Clientes fictícios que já começam na fila, para o console ter quem chamar. */
const DEMO_CUSTOMERS = [
  { uid: 'cliente-demo-1', name: 'Lucas Martins', serviceId: 'corte' },
  { uid: 'cliente-demo-2', name: 'Ana Souza', serviceId: 'combo' },
  { uid: 'cliente-demo-3', name: 'João', serviceId: 'barba' },
] as const;

async function main(): Promise<void> {
  // O seed usa sempre o projeto fixo acima, mas um terminal apontado para um projeto de verdade
  // é sinal de engano: melhor parar aqui.
  for (const name of ['GOOGLE_CLOUD_PROJECT', 'GCLOUD_PROJECT'] as const) {
    const project = process.env[name];
    if (project && !project.startsWith('demo-')) {
      throw new Error(`${name} aponta para "${project}". O seed só roda nos emuladores, com projetos demo-*.`);
    }
  }

  // Antes de `db()`: é este app, com o projeto fixo, que o Firestore das functions passa a usar.
  initializeApp({ projectId: PROJECT_ID });
  // O mesmo Firestore das functions: assim o seed pode usar a transação da fila de verdade.
  const firestore = db();
  const auth = getAuth();

  // Aberta todos os dias, o dia todo, e sem fechar a entrada antes do fim: uma demonstração
  // precisa funcionar na hora em que alguém resolver testar. Uma regra do domínio continua
  // valendo: perto da meia-noite, com barbeiro em expediente, a entrada fecha quando a previsão
  // de atendimento passa das 24:00. Os horários de funcionamento são cobertos pelos testes do
  // domínio.
  const allDay = [{ start: '00:00', end: '24:00' }];

  const shopData = {
    name: 'Barbearia do Zé',
    slug: SHOP_ID,
    timezone: 'America/Sao_Paulo',
    schedule: { sun: allDay, mon: allDay, tue: allDay, wed: allDay, thu: allDay, fri: allDay, sat: allDay },
    services: [
      { id: 'corte', name: 'Corte', defaultDurationMin: 30, active: true },
      { id: 'barba', name: 'Barba', defaultDurationMin: 20, active: true },
      { id: 'combo', name: 'Corte + Barba', defaultDurationMin: 45, active: true },
    ],
    settings: { closeEntryMinutesBefore: 0, openEntryMinutesBefore: 0, maxTicketsPerDay: 200, undoWindowSec: 15 },
    ownerUid: DEMO_BARBERS[0].uid,
    createdAt: Date.now(),
  };
  await firestore.doc(`shops/${SHOP_ID}`).set(shopData);

  for (const barber of DEMO_BARBERS) {
    try {
      await auth.createUser({ uid: barber.uid, email: barber.email, password: DEMO_PASSWORD, displayName: barber.displayName });
    } catch (error) {
      if ((error as { code?: string }).code !== 'auth/uid-already-exists') throw error;
    }
    // O membro e o vínculo lido pelo app depois do login são gravados juntos (ADR 0007).
    await firestore
      .batch()
      .set(firestore.doc(`shops/${SHOP_ID}/members/${barber.uid}`), {
        role: barber.role,
        displayName: barber.displayName,
        active: true,
        joinedAt: Date.now(),
      })
      .set(firestore.doc(`staff/${barber.uid}`), { shopId: SHOP_ID, role: barber.role, updatedAt: Date.now() })
      .commit();
  }

  // Se o dia já existe, a fila está em uso: as callables mantêm tudo e o seed não mexe nela.
  // Senão, grava a projeção da fila vazia de hoje, para /b/:slug já mostrar a fila antes do
  // primeiro comando. Checar e gravar na mesma transação impede o seed de passar por cima da
  // projeção de um comando que criou o dia nesse meio-tempo.
  const nowMs = Date.now();
  const shop = parseShop(SHOP_ID, shopData);
  const dateKey = currentDateKey(shop, nowMs);
  const dayExists = await firestore.runTransaction(async (tx) => {
    if ((await tx.get(refs.day(SHOP_ID, dateKey))).exists) return true;
    const emptyDay = createQueueDay(SHOP_ID, dateKey, nowMs);
    tx.set(refs.publicQueue(SHOP_ID), buildPublicQueue(emptyDay, { nowMs, shop, stats: {} }));
    return false;
  });

  const queued = dayExists ? 0 : await queueDemoCustomers();

  console.log(`✔ Barbearia "${SHOP_ID}" criada (aberta todos os dias, o dia todo).`);
  console.log(`✔ Barbeiros: ${DEMO_BARBERS.map((b) => b.email).join(', ')} (senha: ${DEMO_PASSWORD})`);
  console.log(
    dayExists
      ? '✔ A fila de hoje já existia e foi mantida como estava.'
      : `✔ ${queued} cliente(s) de demonstração na fila.`,
  );

  console.log('… Preparando as functions do emulador (alguns segundos na primeira vez).');
  await warmUpFunctions();
  console.log('✔ Pronto para usar.');
}

/**
 * Põe os clientes de demonstração na fila pelo mesmo caminho da callable `joinQueue` (regra do
 * domínio dentro da transação), para o agregado, a projeção e os tickets ativos nascerem
 * consistentes. Devolve quantos entraram; se algum for recusado, o seed falha em vez de terminar
 * com a fila pela metade.
 */
async function queueDemoCustomers(): Promise<number> {
  for (const customer of DEMO_CUSTOMERS) {
    const requestId = randomUUID();
    const newTicketId = refs.newId();
    await runQueueCommand({
      shopId: SHOP_ID,
      requestId,
      actorUid: customer.uid,
      requireMember: false,
      loadActiveTicket: true,
      execute: ({ day, ctx, activeTicket }) =>
        joinQueue(day, ctx, {
          requestId,
          actorUid: customer.uid,
          newTicketId,
          name: customer.name,
          serviceId: customer.serviceId,
          // Cada cliente tem o próprio uid e o próprio ticket ativo, como quem entra pelo link.
          source: 'link',
          preferredBarberId: null,
          activeTicket,
        }),
    });
  }
  return DEMO_CUSTOMERS.length;
}

/**
 * No emulador, a primeira chamada de cada function carrega o código dela e leva alguns segundos.
 * Uma chamada sem login a cada uma (recusada na hora) adianta esse carregamento, para o primeiro
 * toque no app responder rápido. Sem o emulador de Functions no ar, não faz nada.
 */
async function warmUpFunctions(): Promise<void> {
  await Promise.all(
    Object.keys(callables).map((name) =>
      fetch(`http://${FUNCTIONS_EMULATOR_HOST}/${PROJECT_ID}/${REGION}/${name}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ data: {} }),
      }).catch(() => undefined),
    ),
  );
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
