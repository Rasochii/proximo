---
name: planejar-fase
description: Transforma uma fase do roadmap do Próximo! (F2 a F8) ou um item do plano em tarefas pequenas e ordenadas, cada uma com critério de pronto, arquivos afetados, testes, skill/agente a usar e riscos — antes de escrever código. Use quando o usuário disser "vamos começar a F3", "planeja a próxima fase", "quebra isso em tarefas" ou antes de uma feature grande.
---

# Planejar uma fase

Objetivo: sair com uma lista de tarefas que possam ser feitas e verificadas **uma por vez**, cada uma terminando em um commit pequeno com CI verde. Esta skill **não escreve código**.

## 1. Levantar o contexto (leia, não suponha)

1. `docs/PLANO_DE_ACAO.md`: a seção da fase pedida (objetivo, entregas, "Pronto quando") e a "Definição de pronto".
2. `README.md`: tabela de Roadmap (o que já está ✅ / 🚧).
3. ADRs em `docs/adr/` que a fase toca.
4. O código que existe hoje na área: `app/lib/features/*`, `app/lib/core/*`, `functions/src/*`. Liste o que já está pronto e pode ser reaproveitado, e o que a fase pressupõe mas ainda não existe (dependências de fases anteriores).
5. Se houver issues/PRs abertos relacionados: `gh issue list --search "<fase>"` e `gh pr list` (somente leitura).

## 2. Montar as tarefas

Regras de corte:
- **Fatias verticais** quando possível (dado → estado → tela → teste) em vez de "todas as entidades", "todas as telas".
- Cada tarefa cabe em **até ~meio dia** de trabalho e gera **1 commit/PR** revisável (< ~400 linhas de diff, fora gerados).
- Backend antes do app quando o app depende de contrato novo (callable, campo em `publicQueues`).
- Infra compartilhada (ex.: `Failure`, providers do Firebase) aparece **uma vez**, na primeira tarefa que precisa dela.
- Nada especulativo: se o plano não pede, não entra (YAGNI). Ideias extras vão para "Fora do escopo".

Para cada tarefa:

```
### T<n> — <título no imperativo>
- Entrega: <comportamento observável, 1–2 frases>
- Depende de: <T? / nada>
- Arquivos prováveis: <caminhos>
- Pronto quando:
  - [ ] <critério verificável, ex.: "dois toques simultâneos chamam só 1 cliente (teste de emulador)">
  - [ ] testes: <quais, em que arquivo>
  - [ ] estados de UI: carregando / vazio / erro (se for tela)
- Como fazer: skill `<nova-callable | nova-feature-flutter | strings-l10n>`; revisar com `<agente>`
- Riscos/decisões: <o que pode dar errado ou precisa de decisão do usuário>
- Commit: `<tipo(escopo): mensagem>`
```

## 3. Fechar o plano

Inclua ao final:
- **Ordem sugerida** e o que pode ser feito em paralelo.
- **Decisões em aberto** que só o usuário pode tomar (pergunte de forma objetiva; ofereça uma recomendação).
- **Fora do escopo** (ideias que surgiram e ficaram para depois).
- **Verificação da fase**: como provar o "Pronto quando" da fase inteira (ex.: roteiro manual com a skill `rodar-local` + testes).

## 4. Onde registrar

- Mostre o plano na conversa e espere aprovação ou ajustes.
- Depois de aprovado, ofereça (não faça sem pedido):
  - salvar em `docs/fases/F<n>.md`;
  - criar issues no GitHub, uma por tarefa: `gh issue create --title "F<n>/T<k> — ..." --body-file ...` (exige confirmação);
  - criar a lista de tarefas da sessão para acompanhar a execução.
- Ao executar, siga uma tarefa por vez e marque o critério de pronto antes de passar para a próxima.
