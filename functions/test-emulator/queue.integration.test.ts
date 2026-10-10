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

interface CallError {
  readonly status: string;
  readonly message?: string;
  readonly details?: { code?: string };
}

type CallResult<T> = { readonly ok: true; readonly result: T } | { readonly ok: false; readonly error: CallError };

/** Chama uma callable pelo protocolo HTTP; qualquer resposta fora do contrato vira erro explícito. */
async function call<T>(fn: string, token: string, data: object): Promise<CallResult<T>> {
  const res = await fetch(`${FUNCTIONS}/${fn}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
  });
  const text = await res.text();
  let json: { result?: T; error?: CallError };
  try {
    json = JSON.parse(text) as typeof json;
  } catch {
    return { ok: false, error: { status: `HTTP_${res.status}`, message: text.slice(0, 200) } };
  }
  if (json.error) return { ok: false, error: json.error };
  if (!('result' in json)) return { ok: false, error: { status: `HTTP_${res.status}`, message: 'Resposta sem result' } };
  return { ok: true, result: json.result };
}

/**
 * Executa `fn` sobre os itens com no máximo `limit` chamadas em paralelo.
 * O emulador de Functions atende uma requisição por processo e derruba conexões com 50 de uma vez;
 * em produção cada instância aceita até 80 requisições simultâneas.
 */
async function mapWithConcurrency<T, R>(items: readonly T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await fn(items[index]!, index);
    }
  });
  await Promise.all(workers);
  return results;
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
  assert.ok(started.ok, JSON.stringify(started));
});

after(async () => {
  await Promise.all(getApps().map((app) => deleteApp(app)));
});

describe('concorrência', () => {
  it('50 entradas concorrentes recebem números únicos e sequenciais', async () => {
    const customers = await Promise.all(Array.from({ length: 50 }, () => signUp()));
    const results = await mapWithConcurrency(customers, 10, (c, i) =>
      call<{ number: number }>('joinQueue', c.token, {
        requestId: randomUUID(),
        shopId: SHOP,
        name: `Cliente ${String.fromCharCode(65 + (i % 26))}`,
        serviceId: 'corte',
      }),
    );
    const numbers: number[] = [];
    const failures: CallError[] = [];
    for (const r of results) {
      if (r.ok) numbers.push(r.result.number);
      else failures.push(r.error);
    }
    assert.deepEqual(failures, []);
    assert.deepEqual(numbers.sort((a, b) => a - b), Array.from({ length: 50 }, (_, i) => i + 1));
  });

  it('dois toques simultâneos em "Próximo!" com o mesmo requestId chamam uma única pessoa', async () => {
    const requestId = randomUUID();
    const [a, b] = await Promise.all([
      call<{ called: { ticketId: string } | null }>('callNext', barber.token, { requestId, shopId: SHOP }),
      call<{ called: { ticketId: string } | null }>('callNext', barber.token, { requestId, shopId: SHOP }),
    ]);
    assert.ok(a.ok && b.ok, JSON.stringify([a, b]));
    assert.deepEqual(a.result, b.result);

    const day = (await getFirestore().collection(`shops/${SHOP}/days`).get()).docs[0]!.data() as {
      tickets: { status: string }[];
    };
    assert.equal(day.tickets.filter((t) => t.status === 'called').length, 1);
  });

  it('cliente não pode chamar o próximo', async () => {
    const customer = await signUp();
    const res = await call('callNext', customer.token, { requestId: randomUUID(), shopId: SHOP });
    assert.ok(!res.ok);
    assert.equal(res.error.status, 'PERMISSION_DENIED');
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
