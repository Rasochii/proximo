# ADR 0001 — Firebase como backend

**Status:** aceito · 2026-10-10

## Contexto
O app precisa de tempo real (posição na fila), autenticação anônima (entrar só com o nome), proteção contra abuso de clientes e notificações push. É um projeto solo de portfólio que pode virar produto.

## Decisão
Usar Firebase: Authentication (anônima + e-mail/Google), Cloud Firestore, Cloud Functions (2ª geração, Node 22, `southamerica-east1`), FCM, App Check e Hosting.

## Consequências
- ✅ Auth anônima, App Check e FCM integrados; emuladores permitem desenvolver sem conta paga.
- ✅ Listeners em tempo real nativos no Flutter.
- ⚠️ Relatórios/métricas são mais trabalhosos em NoSQL (mitigado por agregados calculados no servidor).
- ⚠️ Functions em produção exigem plano Blaze → ativar só no deploy, com alerta de orçamento.
- Alternativa considerada: Supabase (melhor para SQL/relatórios; exigiria integrar push e anti-abuso por conta própria).
