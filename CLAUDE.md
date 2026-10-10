# Próximo! — fila virtual para barbearias

Monorepo de portfólio com arquitetura de produto real: app Flutter em `app/`, backend em Cloud Functions TypeScript em `functions/`, além de `firestore.rules` e `docs/`.
Plano completo em `docs/PLANO_DE_ACAO.md` · decisões em `docs/adr/` · regras de cada lado em `app/CLAUDE.md` e `functions/CLAUDE.md`.

## Estado atual

- F0 e F1 prontas: domínio da fila, callables, rules e testes de concorrência.
- F2 em andamento: o app só tem esqueleto (bootstrap, tema, router, l10n). Ainda não existem camada de dados, `Result`/`Failure` nem auth anônima. Quem criar esses itens deve atualizar esta seção.
- Antes de assumir em que fase estamos, confira a tabela de Roadmap no `README.md`.

## Invariantes (só mudam com um ADR novo)

1. **O app nunca escreve no Firestore** (ADR 0004). Toda mutação é uma callable que roda numa transação. O app só lê `publicQueues/{shopId}` e `activeTickets/{uid}`; a equipe também lê `shops/{shopId}/days/{dateKey}`.
2. **A fila do dia é um único documento**, `shops/{shopId}/days/{yyyy-MM-dd}` (ADR 0003). Não use subcoleção de tickets.
3. **O domínio é puro** (`functions/src/domain/`): sem `firebase-*`, sem I/O, sem `Date.now()`. O tempo chega por `ctx.nowMs`, e o ESLint bloqueia os imports proibidos.
4. **Idempotência:** toda callable que altera dados recebe um `requestId` UUID v4 gerado no app, e o mesmo valor é reutilizado nos retries.
5. **Uma fila única com N barbeiros desde o domínio** (ADR 0005), mesmo enquanto a UI mostra só 1 barbeiro.
6. **`publicQueues` não tem dados pessoais:** só rótulo ("Lucas M."), posição e ETA. Nome completo e UID ficam no agregado, que só a equipe lê.
7. **Rules deny-by-default.** Se o modelo de dados mudar, atualize `firestore.rules` e `functions/test-emulator/rules.test.ts` juntos.
8. **Fluxo de erros:** o domínio lança `DomainError` com código estável, a callable devolve `HttpsError` com `details.code` e o app traduz esse código pelo ARB. A mensagem do servidor nunca aparece crua para o usuário.
9. Região `southamerica-east1`, projeto de emulador `demo-proximo`. O fuso de negócio é o da barbearia (`America/Sao_Paulo`), nunca o do dispositivo nem o do servidor.

## Comandos

| O quê | Comando |
|---|---|
| App: análise | `cd app && flutter analyze` |
| App: testes | `cd app && flutter test` |
| App: codegen (riverpod/freezed/json) | `cd app && dart run build_runner build --delete-conflicting-outputs` |
| App: strings | `cd app && flutter gen-l10n` |
| Functions: verificação | `cd functions && npm run typecheck && npm run lint && npm test` |
| Functions: cobertura do domínio (meta ≥ 90%) | `cd functions && npm run test:coverage` |
| Rules e concorrência (precisa de Java 21) | `cd functions && npm run test:emulator` |
| Emuladores e seed | skill `rodar-local` |

O CI (`.github/workflows/ci.yml`) roda exatamente esses comandos.

## Ambiente

- O desenvolvimento é feito no **Windows**. Os comandos precisam funcionar no Git Bash e no PowerShell. Para scripts, use Node portável (veja `functions/scripts/run-tests.mjs`) e não dependa de glob do shell.
- `app/lib/l10n/gen/`, `*.g.dart` e `*.freezed.dart` são gerados e ignorados pelo git. Não edite esses arquivos à mão; um hook bloqueia.
- Não leia nem crie segredos (`.env*` exceto `.env.example`, chaves de service account). Deploy e `git push` só acontecem com pedido explícito.

## Como trabalhar aqui

- Antes de mudar algo, leia o código relacionado e o ADR pertinente, e siga o padrão existente em vez de introduzir outro.
- Faça mudanças pequenas e verificáveis. Não refatore fora do escopo nem adicione dependência sem justificar custo e alternativas.
- Discorde quando houver solução mais simples ou mais segura, explicando o trade-off. Não mude requisito funcional por iniciativa própria.
- Nunca diga que testou ou compilou sem ter rodado. Ao terminar, diga o que foi verificado e o que não foi.
- Antes de commitar, use os revisores: `flutter-reviewer` para `app/`, `backend-reviewer` para `functions/` e `firestore.rules`, e `ux-a11y-reviewer` para telas novas. Testes faltando ficam com o `test-engineer`.
- Antes de começar uma fase ou feature grande, quebre o trabalho em tarefas com a skill `planejar-fase`.
- Para fechar uma tarefa (checklist, commit, ADR), use a skill `fechar-tarefa`.
- Servidores MCP (`.mcp.json`): `dart` serve para análise, testes e inspeção do app rodando; `firebase` serve para Firestore, Auth, Functions e rules. Prefira-os a comandos soltos quando estiverem conectados.

## Definição de pronto

1. `flutter analyze`, `npm run lint` e `npm run typecheck` sem avisos.
2. Toda regra de negócio nova tem teste, e o domínio mantém cobertura ≥ 90%.
3. Nenhum segredo no repositório, e as rules continuam deny-by-default.
4. Commit em Conventional Commits. README e ADR atualizados se alguma decisão mudou.
5. Telas com estados de carregando, vazio e erro, e com `Semantics`.
