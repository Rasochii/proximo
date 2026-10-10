---
name: nova-feature-flutter
description: Como criar ou expandir uma feature no app Flutter do Próximo! seguindo o padrão do projeto — pastas feature-first, Riverpod 3 com codegen, repositório sobre Firestore/Functions, Failure, rota no go_router, strings no ARB e testes. Use ao começar uma tela ou fluxo novo (ex.; console do barbeiro, posição do cliente, onboarding da barbearia).
---

# Nova feature no app

Comece entendendo o fluxo: qual fase do `docs/PLANO_DE_ACAO.md` ela entrega, quais dados lê (`publicQueues`, `activeTickets`, `days`) e quais callables chama. Leia uma feature existente parecida antes de criar arquivos.

## 1. Estrutura (crie só o que a feature usa)

```
app/lib/features/<feature>/
  domain/
    <entidade>.dart               # freezed ou classe final imutável; sem Flutter/Firebase
    <feature>_repository.dart     # contrato — só se houver mais de uma implementação real OU fake em teste
  data/
    <entidade>_dto.dart           # fromJson do Firestore / resultado da callable → entidade
    <feature>_repository_impl.dart
    <feature>_functions.dart      # chamadas às callables (requestId, mapeamento de erro)
  presentation/
    <tela>_page.dart              # Scaffold + composição
    <tela>_controller.dart        # @riverpod Notifier/AsyncNotifier
    widgets/                      # widgets da feature
app/test/features/<feature>/...   # espelha lib/
```

Tela estática sem dados → só `presentation/`.

## 2. Infra compartilhada (verifique antes de criar)

Procure em `lib/core/` antes. Se ainda **não existir** e a feature precisar:
- `lib/core/error/failure.dart` — `sealed class Failure` com subtipos por categoria (rede, permissão, regra de negócio com `DomainErrorCode`, desconhecido) e uma função `failureFromFunctionsException`.
- `lib/core/error/result.dart` — só se o projeto decidir usar `Result`; com Riverpod, `AsyncValue` + exceções tipadas pode bastar. Decida uma vez, registre em `app/CLAUDE.md`.
- `lib/core/firebase/providers.dart` — providers de `FirebaseFirestore`, `FirebaseFunctions` (região `AppConfig.functionsRegion`) e `FirebaseAuth`, para poder sobrescrever nos testes.

Ao criar qualquer um desses, atualize a seção "Estado atual" do `CLAUDE.md` raiz.

## 3. Estado com Riverpod 3

```dart
part '<tela>_controller.g.dart';

@riverpod
Stream<PublicQueue> publicQueue(Ref ref, String shopId) =>
    ref.watch(queueRepositoryProvider).watchPublicQueue(shopId);

@riverpod
class ConsoleController extends _$ConsoleController {
  @override
  FutureOr<void> build() {}

  Future<void> callNext() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => ref.read(queueRepositoryProvider).callNext(...));
    if (!ref.mounted) return;
    state = result;
  }
}
```

- Stream de leitura → provider de `Stream`; comandos → Notifier.
- Efeitos (snackbar de Desfazer, haptics, navegação) com `ref.listen` no widget.
- Depois de editar, rode `dart run build_runner build --delete-conflicting-outputs` (o hook avisa).

## 4. Rota

Em `lib/core/router/app_router.dart`: constante em `AppRoutes`, `GoRoute` com `name`, validação de parâmetros no `redirect` (como o slug). Navegue com `context.goNamed(...)`.

## 5. UI

Siga `app/CLAUDE.md` › UI: `Insets`, `AppTheme`, estados loading/vazio/erro, Semantics, alvo ≥ 48dp, textScale 2.0, web. Strings via skill `strings-l10n`.

## 6. Testes

- Repositório/DTO: unitário com dados reais de exemplo (inclusive campos ausentes/nulos).
- Controller: `ProviderContainer.test(overrides: [...])` com repositório fake; sucesso, falha, `ref.mounted`.
- Tela: um teste de widget por estado (loading, dados, vazio, erro + tentar de novo).
- Telas principais: golden (celular e tablet, claro e escuro).

## 7. Fechamento

`flutter analyze` e `flutter test` limpos → agentes `flutter-reviewer` e `ux-a11y-reviewer` → skill `fechar-tarefa`.
