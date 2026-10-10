# app/ — Flutter

Flutter ≥ 3.32 · Dart ^3.8 · Riverpod 3 + riverpod_generator · go_router 16 · freezed 3 · Firebase (Auth, Firestore, Functions, App Check) · very_good_analysis 9 · mocktail.
Os alvos são Android, iOS e **Web**. A rota `/b/:slug` é aberta pelo QR Code no navegador.

## Estrutura

```
lib/
  main.dart, bootstrap.dart        inicialização única (erros globais, Firebase, ProviderScope)
  app.dart                         MaterialApp.router
  core/{config,firebase,router,theme}
  features/<feature>/{domain,data,presentation}
  l10n/app_pt.arb                  única fonte de strings (gen/ é gerado)
```

A organização é feature-first. Crie `domain/` e `data/` só quando a feature tiver regra ou acesso a dados; telas estáticas ficam só em `presentation/`.

## Camadas

- **domain:** entidades imutáveis (freezed, ou classes `final` simples), contratos de repositório e use cases quando houver orquestração real. Não depende de Flutter nem de Firebase.
- **data:** DTOs com `fromJson`, repositórios que implementam o contrato e datasources de Firestore/Functions. É aqui que exceções viram `Failure`; nenhuma `FirebaseException` chega à UI.
- **presentation:** widgets e Notifiers. Widget não chama Firestore nem Functions e não contém regra de negócio.

A regra de negócio da fila (posição, ETA, transições) **fica no servidor**. O app exibe o que vem de `publicQueues` e chama as callables, sem recalcular posição ou ETA no cliente.

## Riverpod 3

- Providers novos usam `@riverpod` com `part 'x.g.dart'`. O `appRouterProvider` manual pode continuar como está.
- Para ler um stream, crie um provider que retorna `Stream<T>`. A UI trata `AsyncValue` com switch/`when`, cobrindo loading, error e data.
- Comandos ficam em métodos de `Notifier`/`AsyncNotifier`. Depois de um `await`, cheque `ref.mounted` antes de alterar o estado.
- Use `ref.watch` no build, `ref.read` em callbacks e `ref.listen` para efeitos (snackbar, navegação, haptics).
- O Riverpod 3 refaz automaticamente providers que falham. Para erros que não se resolvem tentando de novo (por exemplo, `permission-denied`), configure o `retry`.
- Nos testes, use `ProviderContainer.test(overrides: [...])` e substitua os repositórios por fakes.

## Chamando o backend

- Use uma classe de datasource por área (ex.: `QueueFunctionsDataSource`) com `FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)`.
- Gere o `requestId` (uuid v4) **uma vez por intenção do usuário** e reutilize esse valor no retry. Só repita a chamada em erros transitórios (`unavailable`, `deadline-exceeded`).
- `FirebaseFunctionsException.details['code']` traz o `DomainErrorCode` (a lista está em `functions/src/domain/errors.ts`). Mapeie para um `Failure` tipado e depois para uma string do ARB. Código desconhecido vira a mensagem genérica.
- `firestore.rules` define o que o app pode ler. Uma leitura negada é um bug de modelagem, e a solução nunca é afrouxar a regra no cliente.

## UI

- Material 3 via `AppTheme`. Espaçamentos e raios vêm só de `Insets` (escala de 4 pt). Não use cores nem tamanhos mágicos.
- Os números da fila usam algarismos tabulares (já configurados no tema `display*`).
- Toda tela tem estados de carregando, vazio, erro (com ação de tentar de novo) e, quando fizer sentido, offline.
- Acessibilidade: `Semantics` ou `tooltip` em botões de ícone, alvo de toque ≥ 48 dp, layout que funciona com textScale 2.0 e contraste AA. Mudanças de posição na fila são anunciadas ao leitor de tela.
- No console do barbeiro, a ação principal fica na zona do polegar, e o Desfazer é um SnackBar em vez de diálogo de confirmação.
- Código compartilhado não usa `dart:io`. Ao usar plugins, verifique o suporte a web (`kIsWeb`).
- Use `const` sempre que possível e extraia widgets em classes, não em métodos `_buildX`. Depois de um `await`, cheque `context.mounted`.

## Strings

Toda string visível vai para `lib/l10n/app_pt.arb` (skill `strings-l10n`). Um hook regenera o código quando o ARB muda.

## Testes

- `test/` espelha `lib/`. Use testes unitários para repositórios, mappers e notifiers, testes de widget para os estados de cada tela e goldens para as telas principais do console e do cliente.
- Prefira fakes simples de repositório. Use `mocktail` quando precisar verificar interações.
- O helper `pumpApp` está em `test/widget_test.dart`. Mova-o para `test/helpers/` quando surgir o segundo uso.
