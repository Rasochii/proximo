# Próximo! ✂️

**Fila virtual para barbearias.** O cliente entra na fila pelo QR Code da porta, só com o nome, e espera onde quiser. O barbeiro aperta **"Próximo!"** e o celular de quem é chamado atualiza na hora.

> Projeto de portfólio construído com arquitetura de produto real: Flutter + Riverpod 3 no app, Firebase no backend, regras de negócio puras e testadas, e segurança desde o primeiro commit.

## Destaques técnicos

- **Fila consistente sob concorrência:** toda mutação é uma Cloud Function que roda numa **única transação** sobre o agregado do dia ([ADR 0003](docs/adr/0003-fila-diaria-como-agregado.md)). Números nunca se repetem e dois toques em "Próximo!" nunca chamam duas pessoas.
- **Tempo de espera honesto:** o ETA é calculado por **simulação de eventos** com N barbeiros, intervalos de almoço e fechamento, usando a **mediana** das últimas durações reais de cada serviço ([ADR 0005](docs/adr/0005-fila-unica-n-barbeiros.md)).
- **Domínio puro:** as regras da fila são funções TypeScript sem dependência de Firebase, cobertas por testes unitários.
- **Segurança e LGPD:** Security Rules deny-by-default, nenhuma escrita do cliente ([ADR 0004](docs/adr/0004-mutacoes-somente-no-servidor.md)), App Check, rate limit, idempotência por `requestId`, e projeção pública sem dados pessoais ("Lucas M.").
- **Desfazer em vez de confirmar:** o barbeiro tem alguns segundos para desfazer o último "Próximo!", com detecção de conflito.

## Estrutura

```
proximo/
├── app/                 # Flutter (Riverpod 3, go_router, Material 3)
├── functions/           # Cloud Functions (TypeScript)
│   ├── src/domain/      # regras puras da fila (sem Firebase)
│   ├── src/firebase/    # callables, transações, mapeamento de erros
│   ├── test/            # testes unitários do domínio
│   └── test-emulator/   # Security Rules e concorrência nos emuladores
├── firestore.rules
├── firebase.json        # emuladores (projeto demo-proximo)
└── docs/                # plano de ação e ADRs
```

## Rodando localmente

Tudo roda nos **emuladores do Firebase**: não é preciso conta Firebase, Apple ou Google Play ([ADR 0006](docs/adr/0006-desenvolvimento-local-com-emuladores.md)).

**Pré-requisitos:** Flutter 3.32+ · Node 22 · Java 21 (emulador do Firestore) · Firebase CLI (`npm i -g firebase-tools`).

```sh
git clone https://github.com/Rasochii/proximo.git
cd proximo

# Backend
cd functions
npm install
npm test                 # testes do domínio
npm run test:emulator    # Security Rules + concorrência (sobe e derruba os emuladores)

# App (primeira vez: gera as pastas de plataforma sem sobrescrever o código existente)
cd ../app
flutter create . --project-name proximo --org dev.proximo --platforms android,ios,web
flutter pub get
flutter test
```

Para usar o app com dados de demonstração, use três terminais:

```sh
cd functions && npm run serve    # 1. emuladores (UI em http://localhost:4000)
cd functions && npm run seed     # 2. barbearia demo + barbeiros ze@proximo.dev / joao@proximo.dev (senha: proximo123)
cd app && flutter run -d chrome  # 3. app (no emulador Android o host 10.0.2.2 é usado automaticamente)
```

Em um celular físico: `flutter run --dart-define=EMULATOR_HOST=<IP-do-seu-PC>`.

## Roadmap

O plano completo está em [`docs/PLANO_DE_ACAO.md`](docs/PLANO_DE_ACAO.md).

| Fase | Entrega | Status |
|---|---|---|
| F0 | Fundação do monorepo, emuladores, CI | ✅ |
| F1 | Núcleo da fila no backend (domínio, callables, regras) | ✅ |
| F2 | Fundação do app Flutter (dados, auth anônima, i18n) | 🚧 esqueleto pronto |
| F3 | Console do barbeiro | ⏳ |
| F4 | Experiência do cliente (link/QR, posição ao vivo) | ⏳ |
| F5 | Cadastro da barbearia | ⏳ |
| F6 | Vários barbeiros | ⏳ (domínio já suporta) |
| F7 | Notificações push | ⏳ |
| F8 | Polimento e demo publicada | ⏳ |
