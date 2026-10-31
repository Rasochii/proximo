# ADR 0008 — Portões de qualidade automáticos

**Status:** aceito · 2026-10-31

## Contexto

A revisão de código dependia de uma regra escrita no `CLAUDE.md` ("antes de commitar, use os revisores"). Nada garantia que ela fosse seguida, e ela falhou: as versões finais dos PRs #11 e #12 têm correções feitas depois dos relatórios, que nenhum revisor viu. No GitHub, o check "Revisão" ficava verde mesmo com o veredito "ajustar antes do merge", e nada impedia o merge com CI vermelho. Instrução pede; só um mecanismo fora de quem executa garante.

## Decisão

Quatro portões, cada um cobrindo o que o anterior não alcança:

1. **Trava de commit** (`.githooks/pre-commit`, `.claude/hooks/review-gate.mjs`, regras em `review-rules.mjs`). Um hook de pré-commit do git barra o commit se o que vai ser gravado não tiver aprovação do revisor da área: `flutter-reviewer` para `app/`, `ux-a11y-reviewer` para telas, `backend-reviewer` para `functions/` e `firestore.rules`. Hooks do Claude Code registram o veredito de cada revisor, com a impressão digital (o blob do git) de cada arquivo. O revisor termina o relatório com `VEREDITO: aprovado` ou `VEREDITO: corrigir` (Crítico ou Alto), na última linha; sem isso, conta como não aprovado. O hook `SessionStart` aponta o git para `.githooks`, e um hook `PreToolUse` não deixa o Claude usar `--no-verify` nem mudar `core.hooksPath`.
2. **Veredito como check do PR** (`.github/workflows/claude-review.yml`, `.github/scripts/veredito-revisao.mjs`). A revisão automática publica um marcador com o commit e se há achado bloqueante; o check "Revisão · veredito" falha com achado Crítico ou Alto (no marcador ou em comentário inline), e também se não houver veredito para o commit atual.
3. **Proteção da `main`** (`.github/protecao-main.json`, aplicada por um admin): CI e veredito obrigatórios, sem exceção para administradores.
4. **Dono das travas** (`.github/CODEOWNERS`): PR que mexe nos portões, nas configurações que cobram as invariantes (ESLint, tsconfig, scripts do `package.json`, `firebase.json`, análise do Dart) ou nos `CLAUDE.md`, que a revisão usa como critério, precisa da aprovação da conta dona do repositório. Sem isso, um PR poderia enfraquecer o check que o avalia, porque o workflow de `pull_request` roda a versão do próprio PR. Pelo mesmo motivo, só a conta dona aciona o `@claude`: ele publica como o mesmo usuário da revisão, e outra conta poderia pedir a ele um veredito falso.

Saídas previstas para quando um revisor erra, sempre decididas por uma pessoa: `git commit --no-verify` no terminal dela, para a trava local; um comentário `/contestar <commit>` da conta dona, para o check do PR, que vale só para aquele commit.

## Consequências

- ✅ A revisão deixa de depender de alguém lembrar: o commit e o merge é que exigem.
- ✅ O que `git commit` grava é o que foi revisado, seja qual for a forma do comando.
- ✅ Ordem dos fatores: o portão local é rápido e dá retorno antes do PR; o do GitHub vale para qualquer pessoa ou ferramenta.
- ⚠️ Mais revisões e mais uso de cota: um ajuste pequeno pede nova rodada, e a aprovação vale para todos os arquivos alterados da área, mesmo que o pedido destaque só alguns.
- ⚠️ Um falso positivo do revisor trava o fluxo até alguém decidir. Por isso só Crítico e Alto bloqueiam, e existem as saídas acima.
- ⚠️ Prova que o revisor rodou e aprovou, não que ele acertou. Revisão automática não substitui testes nem o teste manual.
- ⚠️ Commits feitos à mão também passam pela trava; quem quiser pular usa `--no-verify`.
- ⚠️ A trava local é barreira contra esquecimento, não contra má-fé: quem pode editar a máquina pode desligá-la, e `core.hooksPath` é configuração por clone (branches antigos, sem `.githooks`, ficam sem o hook). Contra isso existem a proteção da `main` e o CODEOWNERS, no servidor.
- ⚠️ `git revert` e `git cherry-pick` não executam o pré-commit, e num merge o que veio igual do outro branch não é cobrado aqui. Esses casos ficam com o portão do GitHub.
- ⚠️ PR que muda o workflow da revisão e também código revisado fica sem veredito, porque a ação da revisão recusa rodar com um workflow diferente do da `main`. Aí quem decide é a conta dona, com `/contestar`.
- Alternativa: conferir o comando antes de ele rodar, num hook `PreToolUse` do Claude Code. Foi a primeira versão. Descartada depois de três rodadas de revisão: reimplementava a leitura de shell com expressões regulares (subshell, aspas, `bash -c`, `&`, `--git-dir`), e sempre sobrava uma forma de escapar. O git já sabe o que vai gravar.
- Alternativa: rodar o revisor dentro do hook (tipo `agent`). Descartada: o padrão é 60 segundos e o modelo Haiku, e nossos revisores levam de 3 a 15 minutos.
- Alternativa: fazer o check "Revisão" bloquear em qualquer achado. Descartada: a revisão automática já errou neste projeto (PR #9), e achados Médios e Baixos são para ponderar.
- Alternativa: exigir aprovação humana em todo PR. Descartada por ora: o projeto tem uma pessoa só. Vale apenas para os arquivos dos portões, pelo CODEOWNERS.
- Alternativa: rodar o veredito com `pull_request_target`, a partir da `main`, para o PR não poder alterá-lo. Descartada: em repositório público, esse evento expõe segredos a PRs de fork se usado com descuido, e o check viraria um status à parte, mais complexo. O CODEOWNERS resolve o mesmo problema com um arquivo.
