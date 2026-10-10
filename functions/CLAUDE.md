# functions/ — backend (Cloud Functions + domínio puro)

Node 22 · TypeScript strict (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`) · firebase-functions v2 · firebase-admin 13 · testes com `node:test` via `tsx`.

## Estrutura

```
src/domain/     regras puras: commands, queueDay, eta, schedule, projection, validation, errors, types...
src/firebase/   callables.ts (handlers), queueRepository.ts (transação), errors.ts (DomainError → HttpsError), refs.ts, app.ts
src/index.ts    exporta as callables
test/           unitários do domínio; fixtures.ts tem at(), ctxAt(), emptyDay(), withBarbers(), join(), uuid()
test-emulator/  rules e concorrência (precisa dos emuladores)
scripts/        run-tests.mjs (portável para Windows), seed-emulator.ts
```

## Anatomia de um comando da fila

1. `domain/validation.ts`: `parseXInput(data: unknown)`. Tudo que vem do cliente é `unknown` até passar por aqui, e o `requestId` (UUID v4) é obrigatório.
2. `domain/commands.ts`: uma função pura `(day, ctx, cmd) => CommandOutcome<R>` que passa por `execute(...)`, responsável pela idempotência, pelo histórico `processed` e pela `version`. Efeitos fora do agregado (como `activeTickets`) saem como `Effect`, nunca como escrita direta.
3. `domain/types.ts`: adicione o nome do comando em `CommandName`. Em `domain/errors.ts`, códigos novos entram em `DOMAIN_ERROR_CODES` e em `DEFAULT_MESSAGES`.
4. `firebase/callables.ts`: `callable('nome', ...)` com `runQueueCommand({...})`, definindo `requireMember` corretamente.
5. `firebase/errors.ts`: mapeie o código para um `FunctionsErrorCode` quando ele não for `failed-precondition`.
6. `index.ts`: exporte a callable.

O passo a passo completo, incluindo testes e o cliente Dart, está na skill `nova-callable`.

## Regras

- O domínio não usa `firebase-*`, `Date.now()` nem aleatoriedade. O tempo vem de `ctx.nowMs` e os IDs vêm de fora (como `newTicketId`).
- Imutabilidade: sempre devolva objetos novos (`replaceTickets`, spread) e nunca mute `day`.
- Na transação, **todas as leituras acontecem antes da primeira escrita**. Toda escrita da fila acontece na mesma transação que atualiza `publicQueues`.
- Ações da equipe usam `requireMember: true`. O cliente só age sobre o próprio ticket (`not-ticket-owner`).
- O `logger` nunca recebe nome, e-mail, UID completo nem o payload do cliente.
- O agregado tem limite de 1 MiB. Toda lista nova em `QueueDay` precisa de teto, como `PROCESSED_HISTORY_LIMIT`.
- Chaves `yyyy-MM-dd` e horários seguem o fuso da barbearia (`time.ts`, `schedule.ts`), nunca o UTC do servidor.
- Testes: um `describe` por comando, cobrindo o caminho feliz, cada `DomainError` possível, o replay do mesmo `requestId` e o `request-conflict`. Use `throwsCode` como em `commands.test.ts`. Use `at('2026-10-10T10:00')` para instantes fixos e nunca dependa do relógio real.
- Se você mexer em rules, transação ou concorrência, rode `npm run test:emulator`.
