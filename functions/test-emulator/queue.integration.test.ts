/**
 * Testes de integração das callables nos emuladores (Auth + Firestore + Functions).
 * Foco: consistência sob concorrência. Rodar com: npm run test:emulator
 */
import { deleteApp, getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';

const PROJECT_ID = 'demo-proximo';
const REGION = 'southamerica-east1';
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT_ID}/${REGION}`;
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const SHOP = 'fila-integracao';

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';

/** Cria um usuário no emulador de Auth e devolve o idToken. */
async function signUp(email?: string): Promise<{ uid: string; token: string }> {
  const body = email ? { email, password: 'senha-teste-123', returnSecureToken: true } : { returnSecureToken: true };
  const res = await fetch(`${AUTH}/accounts:signUp?key=fake-api-key`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as { localId: string; idToken: string };
  return { uid: json.localId, token: json.idToken };
}

interface CallResult<T> {
  readonly ok: boolean;
  readonly result?: T;
  readonly error?: { status: string; details?: { code?: string } };
}

async function call<T>(fn: string, token: string, data: object): Promise<CallResult<T>> {
  const res = await fetch(`${FUNCTIONS}/${fn}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
  });
  const json = (await res.json()) as { result?: T; error?: CallResult<T>['error'] };
  return json.error ? { ok: false, error: json.error } : { ok: true, result: json.result as T };
}

/** Horário que cobre o dia todo, para o teste não depender da hora em que roda. */
const allDay = [{ start: '00:00', end: '24:00' }];

let barber: { uid: string; token: string };

before(async () => {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  const db = getFirestore();
  barber = await signUp(`barbeiro-${randomUUID()}@teste.dev`);
  await db.doc(`shops/${SHOP}`).set({
    name: 'Fila de Integração',
    slug: SHOP,
    timezone: 'America/Sao_Paulo',
    schedule: { sun: allDay, mon: allDay, tue: allDay, wed: allDay, thu: allDay, fri: allDay, sat: allDay },
    services: [{ id: 'corte', name: 'Corte', defaultDurationMin: 5 }],
    settings: { closeEntryMinutesBefore: 0, openEntryMinutesBefore: 0, maxTicketsPerDay: 300, undoWindowSec: 15 },
  });
  await db.doc(`shops/${SHOP}/members/${barber.uid}`).set({ role: 'owner', displayName: 'Barbeiro', active: true });
  const started = await call('setBarberStatus', barber.token, { requestId: randomUUID(), shopId: SHOP, status: 'available' });
  assert.equal(started.ok, true, JSON.stringify(started.error));
});

after(async () => {
  await Promise.all(getApps().map((app) => deleteApp(app)));
});

describe('concorrência', () => {
  it('50 entradas simultâneas recebem números únicos e sequenciais', async () => {
    const customers = await Promise.all(Array.from({ length: 50 }, () => signUp()));
    const results = await Promise.all(
      customers.map((c, i) =>
        call<{ number: number }>('joinQueue', c.token, {
          requestId: randomUUID(),
          shopId: SHOP,
          name: `Cliente ${String.fromCharCode(65 + (i % 26))}`,
          serviceId: 'corte',
        }),
      ),
    );
    const failures = results.filter((r) => !r.ok);
    assert.equal(failures.length, 0, JSON.stringify(failures.slice(0, 3)));
    const numbers = results.map((r) => r.result!.number).sort((a, b) => a - b);
    assert.deepEqual(numbers, Array.from({ length: 50 }, (_, i) => i + 1));
  });

  it('dois toques simultâneos em "Próximo!" com o mesmo requestId chamam uma única pessoa', async () => {
    const requestId = randomUUID();
    const [a, b] = await Promise.all([
      call<{ called: { ticketId: string } | null }>('callNext', barber.token, { requestId, shopId: SHOP }),
      call<{ called: { ticketId: string } | null }>('callNext', barber.token, { requestId, shopId: SHOP }),
    ]);
    assert.equal(a.ok && b.ok, true);
    assert.deepEqual(a.result, b.result);

    const day = (await getFirestore().collection(`shops/${SHOP}/days`).get()).docs[0]!.data() as {
      tickets: { status: string }[];
    };
    assert.equal(day.tickets.filter((t) => t.status === 'called').length, 1);
  });

  it('cliente não pode chamar o próximo', async () => {
    const customer = await signUp();
    const res = await call('callNext', customer.token, { requestId: randomUUID(), shopId: SHOP });
    assert.equal(res.ok, false);
    assert.equal(res.error?.status, 'PERMISSION_DENIED');
  });

  it('requisição sem login é recusada', async () => {
    const res = await fetch(`${FUNCTIONS}/joinQueue`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ data: {} }),
    });
    const json = (await res.json()) as { error?: { status: string } };
    assert.equal(json.error?.status, 'UNAUTHENTICATED');
  });
});
