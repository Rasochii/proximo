---
name: nova-callable
description: Passo a passo para criar ou alterar uma Cloud Function callable do Próximo! de ponta a ponta — parse da entrada, comando puro no domínio, códigos de erro, handler com transação, testes unitários e de emulador, rules e o cliente Dart. Use sempre que for adicionar uma ação nova ao backend (ex.; upsertShop, deleteMyData, inviteBarber) ou mudar o contrato de uma existente.
---

# Nova callable (ou mudança de contrato)

Siga na ordem. Cada passo tem um modelo no código existente — **copie o padrão, não invente outro**.

## 0. Decida o tipo

- **Comando da fila** (altera o agregado do dia `shops/{id}/days/{date}`): usa `runQueueCommand` → passos 1–8.
- **Outra mutação** (cadastro da barbearia, convite, exclusão de dados): também roda em transação no handler, mas sem `runQueueCommand`. Mantenha a regra pura em `src/domain/<area>.ts` (ex.: validação de horários já existe em `shop.ts`/`schedule.ts`) e a transação em `src/firebase/<area>Repository.ts`. Passos 1, 3–8 valem igual.

Se a mudança altera uma decisão de ADR (ex.: cliente passaria a escrever), pare e discuta com o usuário antes.

## 1. Contrato de entrada — `src/domain/validation.ts`

- `export interface XInput` + `export function parseXInput(data: unknown): XInput` usando os helpers `asPayload`, `requestId`, `id`, `optionalId`, `oneOf`, `bool`.
- `requestId` obrigatório em toda mutação. Texto livre do usuário fica `unknown` aqui e é saneado no domínio (`sanitizeDisplayName`).
- Teste em `test/validation.test.ts`: payload válido, cada campo inválido/ausente → `invalid-argument` com `details.field`.

## 2. Regra pura — `src/domain/commands.ts`

- `export interface XCommand extends CommandMeta` (ou `BarberCommand`) e `export function x(day, ctx, cmd): CommandOutcome<XResult>` passando por `execute('x', day, ctx, cmd, () => ({ day, result, effects?, stats? }))`.
- Adicione `'x'` a `CommandName` em `types.ts` (e a `UndoableCommand` se tiver Desfazer).
- Sem `Date.now()` (use `ctx.nowMs`), sem IDs aleatórios (receba do handler, como `newTicketId`), sem mutação.
- Efeitos fora do agregado → `Effect` (hoje: `activeTicket.set` / `activeTicket.clear`). Tipo novo de efeito exige tratar em `applyEffect` no repositório.
- Se o resultado muda a visão pública, confirme que `buildPublicQueue` (`projection.ts`) continua sem dados pessoais.

## 3. Erros — `src/domain/errors.ts` e `src/firebase/errors.ts`

- Código novo em `DOMAIN_ERROR_CODES` + mensagem pt-BR em `DEFAULT_MESSAGES` (curta, acionável, sem jargão).
- Se o código não deve virar `failed-precondition`, mapeie em `HTTPS_CODE_BY_DOMAIN_CODE`.
- O app vai traduzir pelo `details.code` (passo 7) — anote o código novo.

## 4. Handler — `src/firebase/callables.ts`

```ts
export const x = callable('x', async (request, uid) => {
  const input = parseXInput(request.data);
  return runQueueCommand({
    shopId: input.shopId,
    requestId: input.requestId,
    actorUid: uid,
    requireMember: true,            // ação de equipe? cliente → false e checar dono no domínio
    // loadActiveTicket: true,      // só se precisar de activeTickets/{uid}
    // rateLimit: { key: 'x', policy: X_RATE_LIMIT }, // ações abertas ao público
    execute: ({ day, ctx, member }) => xCommand(day, ctx, { requestId: input.requestId, actorUid: uid, ... }),
  });
});
```

- Sempre via `callable(...)` (exige auth, aplica `callableOptions` com região e App Check, padroniza erro).
- Exporte em `src/index.ts`.

## 5. Testes unitários — `test/commands.test.ts` (ou `test/<area>.test.ts`)

Um `describe('x')` com, no mínimo:
- caminho feliz: `result`, novo estado, `effects`, `version` + 1;
- cada `DomainError` possível via `throwsCode(...)`;
- replay com o mesmo `requestId` → `replayed: true`, mesmo resultado, nada muda;
- mesmo `requestId` por outro ator/comando → `request-conflict`;
- caso com 2 barbeiros quando a regra envolve barbeiros.

Tempo fixo com `at('2026-10-10T10:00')`. Rode `npm test` e `npm run test:coverage` (≥ 90% em `src/domain/`).

## 6. Rules e emulador

- Novo documento/coleção? Adicione `match` explícito em `firestore.rules` (leitura mínima, `allow write: if false`) e casos em `test-emulator/rules.test.ts`.
- Ação sujeita a corrida (dois toques, muitas entradas)? Adicione cenário em `test-emulator/queue.integration.test.ts`.
- Rode `npm run test:emulator` (Java 21 + Firebase CLI). Se não der para rodar, diga explicitamente.

## 7. Cliente Dart — `app/`

- Método no datasource de Functions da feature: `FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion).httpsCallable('x')`.
- `requestId` = uuid v4 criado **uma vez** por intenção do usuário e reutilizado no retry.
- Mapear `details['code']` → `Failure`; mensagem nova no ARB (skill `strings-l10n`).
- Teste unitário do mapeamento de erro e do retry.

## 8. Fechamento

- `cd functions && npm run typecheck && npm run lint && npm test`.
- Peça revisão ao agente `backend-reviewer`.
- Contrato novo/alterado → atualizar a tabela do modelo de dados em `docs/PLANO_DE_ACAO.md` se mudou; ADR se mudou decisão.
- Commit: `feat(functions): ...` (skill `fechar-tarefa`).
