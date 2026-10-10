---
name: fechar-tarefa
description: Checklist para concluir uma tarefa no Próximo! — verificações automáticas, revisão pelos agentes, documentação (README, plano, ADR) e commit em Conventional Commits. Use ao terminar uma implementação, antes de commitar ou abrir PR, ou quando o usuário disser "pode fechar", "commita" ou "abre o PR".
---

# Fechar uma tarefa

## 1. Verificar (rode de verdade; não assuma)

Só as áreas tocadas:

```sh
# app/
cd app && flutter analyze && flutter test
# functions/
cd functions && npm run typecheck && npm run lint && npm test && npm run test:coverage
# firestore.rules, transações ou concorrência
cd functions && npm run test:emulator
```

Se algum comando não puder rodar (ex.: sem Java), registre isso no resumo final.

## 2. Revisar

- `app/` → agente `flutter-reviewer`; telas → `ux-a11y-reviewer`.
- `functions/` ou `firestore.rules` → `backend-reviewer`.
- Corrija achados Crítico/Alto. Médio/Baixo: corrija ou liste para o usuário decidir.

## 3. Definição de pronto

- [ ] Lints e typecheck sem avisos.
- [ ] Regra de negócio nova com teste; domínio ≥ 90% de cobertura.
- [ ] Sem segredo no diff (`git diff --staged` — procure chaves, tokens, `.env`).
- [ ] Rules deny-by-default; `publicQueues` sem dados pessoais.
- [ ] Telas com loading/vazio/erro e Semantics; strings no ARB.
- [ ] Nada fora do escopo pedido no diff.

## 4. Documentar (só se mudou)

- **README.md**: status da fase na tabela de Roadmap; instruções de execução.
- **docs/PLANO_DE_ACAO.md**: modelo de dados, ciclo do ticket, escopo de fase.
- **CLAUDE.md** raiz: seção "Estado atual" quando uma peça de infra nova passa a existir.
- **ADR** quando uma decisão arquitetural é tomada ou revertida: `docs/adr/NNNN-titulo-em-kebab.md`, próximo número livre, formato dos existentes:

```markdown
# ADR NNNN — <Título>

**Status:** aceito · AAAA-MM-DD

## Contexto
<o problema e as forças em jogo>

## Decisão
<o que foi decidido, de forma verificável>

## Consequências
- ✅ <ganho>
- ⚠️ <custo ou risco>
- Alternativa: <o que foi considerado e por que não>
```

## 5. Commit

Conventional Commits em pt-BR, escopo = área:

```
feat(app): console do barbeiro com Próximo! e Desfazer
fix(functions): impede undoLast após nova chamada de outro barbeiro
test(functions): concorrência de entradas simultâneas
docs(adr): 0007 notificações via FCM
chore(ci): cache do pub
```

- Um assunto por commit; corpo explica o **porquê** quando não for óbvio.
- Branch `feat/*` / `fix/*`; nunca commitar direto na `main` sem o usuário pedir.
- **Não** faça `git push`, deploy ou abra PR sem pedido explícito.

## 6. Resumo para o usuário

O que mudou (1–3 linhas), o que foi verificado (comandos e resultado), o que ficou pendente ou não verificado, e riscos conhecidos.
