---
name: strings-l10n
description: Como adicionar ou alterar textos visíveis no app Flutter do Próximo! via ARB (app/lib/l10n/app_pt.arb) — nomes de chave, placeholders, plurais, mensagens de erro por código de domínio e uso nos widgets. Use sempre que uma tela precisar de texto novo ou ao traduzir erros do backend.
---

# Strings e localização

Fonte única: `app/lib/l10n/app_pt.arb` (template, pt-BR). O código gerado vai para `app/lib/l10n/gen/` (ignorado pelo git) — **nunca edite o gerado**. O hook do projeto roda `flutter gen-l10n` ao salvar o ARB; sem hook, rode `cd app && flutter gen-l10n`.

## Nomes de chave

`<tela ou área><Elemento>` em camelCase, como as existentes: `homeJoinTitle`, `homeJoinAction`, `notFoundTitle`.
- Ações de botão terminam em `Action`; títulos em `Title`; dicas em `Hint`.
- Erros do backend: `error` + código em camelCase → `errorEntriesClosed` para `entries-closed`.
- Reaproveite chaves genéricas (`backToHome`) só quando o sentido for idêntico.

## Placeholders e plurais

```json
"queuePosition": "Você é o {position}º da fila",
"@queuePosition": {
  "placeholders": { "position": { "type": "int" } }
},
"queuePeopleAhead": "{count, plural, =0{Ninguém na sua frente} =1{1 pessoa na sua frente} other{{count} pessoas na sua frente}}",
"@queuePeopleAhead": {
  "placeholders": { "count": { "type": "int" } }
},
"etaRange": "Entre {min} e {max} min",
"@etaRange": {
  "placeholders": { "min": { "type": "int" }, "max": { "type": "int" } }
}
```

Use plural ICU em vez de `if` no código. Datas/horas: placeholder `DateTime` com `format` (ex.: `"Hm"`) — sempre no fuso da barbearia, convertido antes.

## Uso

```dart
final l10n = AppLocalizations.of(context);
Text(l10n.queuePeopleAhead(ahead));
```

`nullable-getter: false` está ativo, então `AppLocalizations.of(context)` não é nulo.

## Erros de domínio

Os códigos estão em `functions/src/domain/errors.ts` (`DOMAIN_ERROR_CODES`). Para cada código que o usuário pode ver, crie a chave `error<Codigo>` e mapeie num único lugar (ex.: extensão `Failure.message(AppLocalizations l10n)` em `lib/core/error/`), com fallback `errorUnexpected`. Texto: diga o que aconteceu e o que fazer ("A barbearia não está aceitando entradas agora. Tente de novo em alguns minutos.").

## Estilo do texto

pt-BR, direto e cordial, segunda pessoa ("você"). Botões com verbo ("Entrar na fila", "Sair da fila", "Próximo!"). Sem jargão técnico, sem culpar o usuário.

## Testes

Testes de widget procuram texto em pt-BR (como `test/widget_test.dart`). Se mudar um texto, atualize os testes que o usam.
