# ADR 0006 — Desenvolvimento 100% local com o Firebase Emulator Suite

**Status:** aceito · 2026-10-10

## Decisão
O projeto usa o id `demo-proximo` nos emuladores (projetos `demo-*` não acessam nenhum recurso real). O app Flutter, no ambiente `emulator`, inicializa o Firebase com opções fictícias e se conecta aos emuladores locais. Um script de seed cria a barbearia de demonstração.

## Consequências
- ✅ Nenhuma conta Apple, Google Play ou Firebase é necessária para desenvolver e demonstrar localmente.
- ✅ Testes de integração e de Security Rules rodam no CI.
- ⚠️ Antes do deploy real será preciso `flutterfire configure` e a criação do projeto Firebase.
