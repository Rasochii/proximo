---
name: rodar-local
description: Como subir os emuladores do Firebase, popular dados de demonstração e rodar o app Flutter do Próximo! localmente no Windows (Chrome, emulador Android, celular físico), além de diagnosticar problemas comuns de conexão. Use quando precisar testar um fluxo de ponta a ponta, reproduzir um bug ou validar a integração app ↔ backend.
---

# Rodar localmente

Tudo roda nos emuladores com o projeto `demo-proximo` (ADR 0006) — não precisa de conta Firebase. Pré-requisitos: Flutter ≥ 3.32, Node 22, **Java 21** (emulador do Firestore), Firebase CLI (`npm i -g firebase-tools`).

## Primeira vez

```sh
cd functions && npm install
cd ../app && flutter pub get && flutter gen-l10n
# se houver @riverpod/@freezed:
dart run build_runner build --delete-conflicting-outputs
```

## Três terminais

```sh
# 1. emuladores (Auth 9099, Firestore 8080, Functions 5001, Hosting 5000, UI http://localhost:4000)
cd functions && npm run serve

# 2. dados de demonstração (barbearia demo + barbeiros)
cd functions && npm run seed
#    barbeiros: ze@proximo.dev / joao@proximo.dev — senha proximo123

# 3. app
cd app && flutter run -d chrome
```

- Emulador Android: o app usa `10.0.2.2` automaticamente.
- Celular físico (mesma rede Wi-Fi): `flutter run --dart-define=EMULATOR_HOST=<IP-do-PC>`; libere as portas 8080, 5001 e 9099 no Firewall do Windows.
- Mudou código em `functions/src`? `npm run serve` faz o build só ao iniciar — rode `npm run build:watch` num quarto terminal para recarregar.

## Testes que dependem dos emuladores

`cd functions && npm run test:emulator` sobe e derruba os emuladores sozinho. **Não** rode com `npm run serve` aberto (conflito de portas).

## Problemas comuns

| Sintoma | Causa provável / solução |
|---|---|
| `Could not start Firestore Emulator, port taken` | Emulador anterior ainda vivo. `npx kill-port 8080 5001 9099 4000` ou feche o processo `java`. |
| Firestore emulator não sobe | Java ausente ou < 21: `java -version`. |
| Callable responde `NOT_FOUND` | Função não exportada em `src/index.ts`, build desatualizado, ou região diferente de `southamerica-east1` no app. |
| Callable responde `unauthenticated` | App não fez login (nem anônimo) antes da chamada, ou Auth não está conectado ao emulador. |
| `permission-denied` na leitura | Rules negando: o app tentou ler um caminho que não é público. Confira `firestore.rules`. |
| App web não conecta | Rodou com `--dart-define=ENV=prod` sem querer, ou `EMULATOR_HOST` apontando para IP errado. |
| Dados somem ao reiniciar | Normal. Para persistir: `firebase emulators:start --import=./emulator-data --export-on-exit` (pasta já ignorada no git). |

## Ao verificar um fluxo

Diga ao usuário exatamente o que foi exercitado (quais telas/callables, com quais dados) e o que não foi — rodar o app não substitui os testes automatizados.
