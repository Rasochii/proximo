/**
 * Testes das Security Rules no emulador do Firestore.
 * Rodar com: npm run test:emulator
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, where } from 'firebase/firestore';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { after, before, beforeEach, describe, it } from 'node:test';

const SHOP = 'barbearia-do-ze';
const DAY = `shops/${SHOP}/days/2026-10-10`;
let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-proximo-rules',
    firestore: { rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `shops/${SHOP}`), { name: 'Barbearia do Zé' });
    await setDoc(doc(db, `shops/${SHOP}/members/ze`), { role: 'owner', displayName: 'Zé', active: true });
    await setDoc(doc(db, `shops/${SHOP}/members/ex`), { role: 'barber', displayName: 'Ex', active: false });
    await setDoc(doc(db, DAY), { tickets: [] });
    await setDoc(doc(db, `shops/${SHOP}/private/stats`), { services: {} });
    await setDoc(doc(db, `publicQueues/${SHOP}`), { waiting: [] });
    await setDoc(doc(db, 'activeTickets/cliente'), { shopId: SHOP, ticketId: 't1' });
    await setDoc(doc(db, 'rateLimits/cliente'), { join: [] });
    await setDoc(doc(db, 'staff/ze'), { shopId: SHOP, role: 'owner' });
  });
});

const asGuest = () => env.unauthenticatedContext().firestore();
const asUser = (uid: string) => env.authenticatedContext(uid).firestore();

describe('leitura', () => {
  it('qualquer um lê o perfil da barbearia e a projeção pública', async () => {
    await assertSucceeds(getDoc(doc(asGuest(), `shops/${SHOP}`)));
    await assertSucceeds(getDoc(doc(asGuest(), `publicQueues/${SHOP}`)));
  });

  it('só a equipe ativa lê o agregado do dia e as estatísticas', async () => {
    await assertSucceeds(getDoc(doc(asUser('ze'), DAY)));
    await assertSucceeds(getDoc(doc(asUser('ze'), `shops/${SHOP}/private/stats`)));
    await assertFails(getDoc(doc(asUser('cliente'), DAY)));
    await assertFails(getDoc(doc(asUser('ex'), DAY)));
    await assertFails(getDoc(doc(asGuest(), DAY)));
  });

  it('ticket ativo só é visível para o dono', async () => {
    await assertSucceeds(getDoc(doc(asUser('cliente'), 'activeTickets/cliente')));
    await assertFails(getDoc(doc(asUser('outro'), 'activeTickets/cliente')));
    await assertFails(getDoc(doc(asGuest(), 'activeTickets/cliente')));
  });

  it('vínculo de equipe só é visível para o próprio usuário', async () => {
    await assertSucceeds(getDoc(doc(asUser('ze'), 'staff/ze')));
    await assertFails(getDoc(doc(asUser('cliente'), 'staff/ze')));
    await assertFails(getDoc(doc(asGuest(), 'staff/ze')));
  });

  it('quem não é de nenhuma equipe lê o próprio vínculo como inexistente, sem erro', async () => {
    await assertSucceeds(getDoc(doc(asUser('cliente'), 'staff/cliente')));
  });

  it('ninguém lista os vínculos de equipe', async () => {
    await assertFails(getDocs(collection(asUser('ze'), 'staff')));
    await assertFails(getDocs(query(collection(asUser('ze'), 'staff'), where('shopId', '==', SHOP))));
  });

  it('ninguém lê os rate limits', async () => {
    await assertFails(getDoc(doc(asUser('cliente'), 'rateLimits/cliente')));
  });
});

describe('escrita', () => {
  it('nenhum cliente escreve em nada — nem a equipe', async () => {
    for (const uid of ['ze', 'cliente']) {
      const db = asUser(uid);
      await assertFails(setDoc(doc(db, `shops/${SHOP}`), { name: 'Hack' }));
      await assertFails(setDoc(doc(db, DAY), { tickets: [] }));
      await assertFails(setDoc(doc(db, `publicQueues/${SHOP}`), { waiting: [] }));
      await assertFails(setDoc(doc(db, `activeTickets/${uid}`), { ticketId: 'x' }));
      await assertFails(setDoc(doc(db, `shops/${SHOP}/members/${uid}`), { role: 'owner', active: true }));
      await assertFails(setDoc(doc(db, `staff/${uid}`), { shopId: SHOP, role: 'owner' }));
      await assertFails(deleteDoc(doc(db, `staff/${uid}`)));
    }
  });
});
