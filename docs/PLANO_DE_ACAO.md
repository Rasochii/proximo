# Próximo! — Plano de Ação

> Fila virtual para barbearias. Projeto de portfólio com arquitetura pronta para uso real.
> Stack: **Flutter + Riverpod 3 + go_router** no app, **Firebase** (Auth, Firestore, Cloud Functions, FCM, App Check, Hosting) no backend.

**Caso de uso principal:** o cliente vê o movimento da barbearia e entra na fila **sem sair de casa**, e só se desloca quando a vez está chegando. Quem depende de transporte pago não pode chegar, encontrar a barbearia cheia e ter de voltar depois. O QR Code da porta é um segundo caminho de entrada, não o único. Disso saem três necessidades além da fila em si: achar a barbearia de longe (F4 e F5), saber a hora de sair (F7) e lidar com quem entrou de longe e não apareceu (o "Não veio" do barbeiro).

## 1. Decisões fechadas

| # | Decisão | Por quê |
|---|---|---|
| D1 | **Firebase** como backend | Login anônimo, App Check e notificações push prontos; emuladores locais permitem desenvolver sem conta paga. |
| D2 | **Riverpod 3** (com code generation) | Projeto solo, estado essencialmente reativo (streams da fila), DI embutida e testável com overrides. |
| D3 | **Fila única por barbearia com N barbeiros desde o domínio** | O MVP roda com 1 barbeiro, mas o motor já distribui a fila entre vários. A fase F6 só adiciona UI, convites e preferência por barbeiro. |
| D4 | **Toda mutação da fila no servidor** (Cloud Functions callable + transação) | Elimina condições de corrida e impede que o cliente adultere posição/ETA. O app só lê. |
| D5 | **Fila do dia = um agregado em um único documento** | Consistência trivial (uma transação, um documento), leitura barata, limite de tamanho folgado (~300 tickets/dia ≈ 100 KB). |
| D6 | **Desenvolvimento 100% local nos emuladores** (projeto `demo-proximo`) | Sem conta Apple/Google/Firebase até a hora de publicar a demo. |
| D7 | **Monorepo** (`app/`, `functions/`, regras e docs juntos) | Um único repositório de portfólio, com CI único e histórico coerente. |
| D8 | Região **southamerica-east1** (São Paulo) | Menor latência para o público-alvo. |

Detalhes e trade-offs em [`docs/adr/`](adr/).

> ⚠️ **Custo:** Cloud Functions em produção exigem o plano **Blaze** (pago por uso). Para portfólio o uso fica dentro da cota gratuita; quando chegar a hora do deploy, ativar o Blaze **com alerta de orçamento** (ex.: US$ 1). Até lá, tudo roda no emulador.

## 2. Arquitetura em uma página

```
┌──────────────── app/ (Flutter) ─────────────────┐        ┌──────────── functions/ (TypeScript) ────────────┐
│ presentation  → widgets + Notifiers (Riverpod)  │        │ firebase/  callables, transações, mapeamento    │
│ domain        → entidades, use cases, contratos │──call─▶│            de erros, App Check, rate limit      │
│ data          → repositórios, DTOs, datasources │        │ domain/    regras PURAS da fila (sem Firebase): │
│                 (Firestore streams + callables) │◀─read──│            horários, ETA, comandos, projeção    │
└─────────────────────────────────────────────────┘        └─────────────────────────────────────────────────┘
                         ▲  leitura em tempo real                         │ escreve na mesma transação
                         └──────────── Firestore: publicQueues/{shopId} ◀─┘  (projeção pública, sem dados pessoais)
```

**Modelo de dados**

| Caminho | Conteúdo | Quem lê | Quem escreve |
|---|---|---|---|
| `shops/{shopId}` | Nome, slug, fuso, horários semanais com intervalos, serviços, configurações | Todos | Servidor |
| `shops/{shopId}/members/{uid}` | Papel (`owner`/`barber`), nome, ativo | O próprio membro e a equipe | Servidor |
| `shops/{shopId}/days/{yyyy-MM-dd}` | **Agregado da fila do dia**: tickets, barbeiros do dia, desfazer, idempotência | Equipe | Servidor |
| `shops/{shopId}/private/stats` | Últimas durações por serviço (mediana alimenta o ETA) | Equipe | Servidor |
| `publicQueues/{shopId}` | Projeção pública: posição, rótulo ("Lucas M."), ETA, quem está sendo atendido e até quando vale (`validUntil`, o fim do dia da barbearia) | Todos | Servidor |
| `activeTickets/{uid}` | Ticket ativo do usuário (garante 1 por pessoa) | O próprio usuário | Servidor |
| `staff/{uid}` | Vínculo de equipe: `shopId` e papel ([ADR 0007](adr/0007-vinculo-de-equipe-em-staff.md)) | O próprio usuário | Servidor |
| `rateLimits/{uid}` | Janela de tentativas | Ninguém | Servidor |

**Ciclo de vida do ticket**

```
waiting ──callNext──▶ called ──callNext/finish (done)────▶ done
   │                     └────callNext/finish (no_show)─▶ no_show
   ├──leaveQueue (cliente)──▶ cancelled      (cliente também pode sair quando já chamado)
   └──removeTicket (barbeiro)─▶ removed
```

O botão **"Próximo!"** finaliza o cliente atual (atendido ou "não veio") e chama o próximo **numa única operação atômica**, com **Desfazer** por alguns segundos.

## 3. Fases

Legenda de tamanho: **P** ≈ 1–3 dias · **M** ≈ 1 semana · **G** ≈ 2 semanas (dev solo, meio período).

### F0 — Fundação · P
**Objetivo:** repositório pronto para crescer com qualidade.
- Monorepo `app/` + `functions/` + `firestore.rules` + `firebase.json` com emuladores (Auth, Firestore, Functions, Hosting).
- Lints rígidos (Dart: `very_good_analysis`; TS: `strict` + ESLint).
- CI no GitHub Actions: análise, testes e build de `app/` e `functions/`.
- Convenções: Conventional Commits, branches `feat/*`, PRs pequenos, ADRs.

**Pronto quando:** `firebase emulators:start` sobe; `npm test` e `flutter analyze` passam no CI.

### F1 — Núcleo da fila no backend · M  ← *começamos aqui*
**Objetivo:** o coração do sistema correto, testado e seguro antes de qualquer tela.
- Domínio puro em TypeScript: horários com intervalos e fuso, **ETA simulando N barbeiros e intervalos**, comandos (`joinQueue`, `leaveQueue`, `callNext`, `finishCurrent`, `undoLast`, `removeTicket`, `setBarberStatus`, `setAcceptingEntries`), idempotência por `requestId`, projeção pública, estatísticas por mediana, rate limit e saneamento de nome.
- Adaptador Firebase: callables com transação, verificação de papel do membro, App Check configurável, mapeamento de erros com mensagens em pt-BR.
- `firestore.rules` deny-by-default + testes das regras.
- Script de seed para o emulador (barbearia demo, serviços, barbeiro).

**Pronto quando:** cobertura do domínio ≥ 90%; testes de concorrência no emulador (50 entradas simultâneas → números únicos e sequenciais; dois "Próximo!" simultâneos → um único chamado); regras testadas.

### F2 — Fundação do app Flutter · M
- Bootstrap com flavors via `--dart-define` (`emulator`, `prod`), conexão automática aos emuladores.
- Core: tema Material 3 (claro/escuro), tipografia, tokens de espaçamento, `go_router` com deep link `/b/:slug`, `Result`/`Failure`, i18n (ARB, pt-BR).
- Auth anônima com upgrade de conta posterior.
- Camada de dados da fila: stream de `publicQueues`, chamadas às callables com `requestId` (UUID) e retry seguro.

**Pronto quando:** app conecta nos emuladores, lê a fila do seed em tempo real; testes unitários dos repositórios com fakes.

### F3 — Console do barbeiro · M
- Login do barbeiro (e-mail/Google no emulador).
- "Iniciar expediente" / pausar / encerrar.
- **"Próximo!"** gigante na zona do polegar mostrando quem será chamado; "Não veio"; **Desfazer** via snackbar; remover ticket por swipe; "Fechar entrada".
- Haptics, `wakelock`, layout tablet (lista + atendimento lado a lado).

**Pronto quando:** fluxo completo sem tocar no Firestore manualmente; testes de widget do console; golden tests das telas principais.

### F4 — Experiência do cliente · M
- Rota `/b/:slug` (funciona no Flutter Web para QR Code), com URL por caminho, sem `#`. O link do QR Code leva direto à fila; com o app instalado, abre no app (App Links no Android, Universal Links no iOS). O Firebase Dynamic Links foi descontinuado e não é usado.
- Entrar só com nome + serviço; mostrar ETA **antes** de entrar. Entrar na fila nunca exige cadastro.
- **Conta de cliente opcional:** depois de entrar, o cliente pode criar uma conta (e-mail ou Google) mantendo o mesmo usuário (a conta anônima é promovida, o ticket continua), para guardar o nome e acompanhar a fila em outro aparelho.
- **Minhas barbearias:** o app lembra as barbearias em que a pessoa já esteve (guardadas no aparelho, sem exigir conta; com conta, acompanham a pessoa em outros aparelhos). A tela inicial passa a mostrá-las com o movimento atual, para entrar na fila de casa com um toque.
- **Convite para instalar o app** na versão web da fila, num aviso dispensável. Enquanto não houver app publicado nas lojas, o convite é "adicionar à tela inicial" (PWA).
- Tela de posição em tempo real: posição em destaque, faixa de ETA, linha do tempo de status, "Sair da fila".
- "Sair da fila" com rede ruim: `leaveQueue` não reaproveita o `requestId` entre toques. Quem saiu sem receber a resposta e toca de novo recebe `invalid-ticket-state`, que hoje vira a mensagem genérica. O controller do cliente deve tratar esse código e `ticket-not-found` como "já saiu".
- Estados: entrada fechada, fora do horário, fila vazia, "é sua vez!".
- **Excluir meus dados** (LGPD + exigência das lojas): callable que anonimiza tickets e apaga a conta anônima.
- Decidir o que acontece quando um cliente com ticket ativo abre o login da equipe: o login por e-mail substitui a sessão anônima, e o cliente perderia a posição e o "Sair da fila". Hoje nada cria sessão anônima, então o risco só começa nesta fase.

**Pronto quando:** dois navegadores (cliente e barbeiro) se atualizam em tempo real; acessibilidade validada (Semantics, contraste, fonte grande).

### F5 — Cadastro da barbearia · M
- **Criar conta do dono** (e-mail e senha) a partir da tela de login. Conta nova não tem barbearia e cai no aviso "conta sem barbearia", que ganha a ação "Criar minha barbearia".
- Onboarding do dono em 3 passos: dados → horários semanais com intervalos → serviços.
- Callable `upsertShop` com validação de horário no domínio (já existe em F1). Ao criar, grava a barbearia, o dono em `members/{uid}` e o vínculo `staff/{uid}` na mesma transação (ADR 0007).
- **Endereço e localização** no cadastro, para a barbearia poder ser encontrada.
- **Encontrar barbearias:** busca por nome e lista das barbearias por perto (geolocalização, com permissão pedida só quando a pessoa usa a função). Depende do endereço acima; a localização do cliente não é guardada no servidor.
- Gerar QR Code/cartaz para impressão; slug único. O cartaz traz o QR Code e, embaixo, o código da barbearia (o slug) para quem preferir digitar no site.

**Pronto quando:** uma barbearia nova é criada pelo app e recebe clientes sem seed.

### F6 — Vários barbeiros · M  ← *antecipado a pedido*
- Convite de barbeiro (link/código), papéis `owner`/`barber`.
- Cada barbeiro com seu "Próximo!" na mesma fila única (o domínio já suporta).
- Preferência por barbeiro opcional ("quero o João") com aviso de espera maior.
- Painel do dono com todos os barbeiros.

**Pronto quando:** 2 barbeiros chamando em paralelo sem conflito; ETA reflete N barbeiros.

### F7 — Notificações e tempo real fino · P
- FCM: "faltam 2 na sua frente" e "é sua vez!".
- Function agendada para atualizar ETAs a cada 5 min em fila parada.
- (Opcional) notificação em andamento no Android.

### F8 — Polimento de portfólio · M
- README com GIFs, diagramas e explicação das decisões.
- Deploy da demo web (Firebase Hosting) com dados de exemplo.
- Badges de CI e cobertura; dark mode; animações; acessibilidade revisada.
- Painel de TV (`/tv/:slug`) como bônus visual.

### Depois (backlog)
Agendamento híbrido, WhatsApp, Pix, fidelidade, métricas avançadas, Live Activities, geofence.

### Decisões adiadas
Pontos conhecidos e deixados de fora de propósito na F3, com o motivo. Os dois primeiros precisam estar resolvidos antes do primeiro deploy real.

| Ponto | Por que ficou | Quando resolver |
|---|---|---|
| `publicQueues` traz o UID do barbeiro (`barbers[].id`, `nowServing[].barberId` e `waiting[].preferredBarberId`), e a invariante 6 diz que UID fica no agregado. | Já existia, e o console se reconhece por esse campo. Corrigir é escolher entre um identificador opaco e um ADR aceitando o UID da equipe. | Antes do primeiro deploy |
| Backend e app precisam sair juntos: sem `expectedServingTicketId`, a callable recusa com `invalid-argument`, e um console antigo para de avançar a fila. | Até aqui só rodamos nos emuladores. | No primeiro deploy e em toda mudança de contrato |
| `undoLast` não confere qual avanço está desfazendo. Com dois aparelhos, o toque em um pode desfazer o avanço feito no outro. | Exige mudar o contrato e o app, e o risco cabe na janela de desfazer. | Mudança própria, ainda na F3 ou na F6 |
| O servidor não informa quanto resta da janela de desfazer (`undoRemainingMs`). Uma repetição aplicada tarde pode ficar sem o aviso. | O app conta do envio e erra para menos, o que é seguro. | Quando houver reclamação de uso ou na F6 |
| Desfazer pode reabrir o atendimento de quem já entrou em outra barbearia dentro da janela. `activeTickets` continua apontando para a outra, e o cliente não vê o ticket reaberto. | Resolver exige ler o `activeTickets` do cliente na transação, e hoje só o do ator é lido. Não corrompe dados. | F5, quando existir mais de uma barbearia |
| Celular deitado com letra em dobro em tela muito baixa (640×360 e 568×320): o motivo de uma recusa fica em parte cortado e exige rolar a barra. | O botão principal e o Desfazer têm prioridade, e os dois continuam à vista. | F3, com o layout tablet |
| Suspeita, por cálculo: com o celular deitado e letra em dobro, o aviso "Anterior não veio. Chamado: …" pode ocupar três linhas e passar da reserva de duas. | Não foi reproduzida. A saída seria encurtar o texto ou limitar as linhas do aviso. | F3, com o layout tablet |
| Barbeiro desativado (`members/{uid}.active = false`) deixa o cliente na cadeira sem ninguém que possa finalizar. | Depende do fluxo de equipe. | F6, com uma ação do dono para assumir a cadeira |

## 4. Definição de pronto (vale para toda tarefa)
1. `flutter analyze` / `npm run lint` sem avisos.
2. Testes novos para toda regra de negócio; domínio com cobertura ≥ 90%.
3. Nenhum segredo no repositório; regras deny-by-default.
4. Commit no padrão Conventional Commits; README/ADR atualizados se a decisão mudou.
5. Telas com estados de carregando, vazio e erro, e com Semantics.

## 5. Riscos técnicos e mitigação
| Risco | Mitigação |
|---|---|
| Corrida em entradas/chamadas simultâneas | Agregado diário em um documento + transação no servidor + `requestId` idempotente. |
| Abuso de entradas anônimas | 1 ticket ativo por usuário, rate limit por UID, App Check, remoção pelo barbeiro, nome saneado. |
| ETA ruim | Mediana das últimas 20 durações por serviço (resiste a outliers), simulação com intervalos e N barbeiros, exibido como faixa. |
| Barbeiro esquece de apertar "Próximo!" | Um botão só faz tudo (finaliza + chama); lembrete em F7. |
| Custos | Emuladores no dev; Blaze com alerta de orçamento só no deploy. |
