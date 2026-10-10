# ADR 0004 — Mutações da fila somente no servidor

**Status:** aceito · 2026-10-10

## Decisão
O cliente nunca escreve em coleções da fila. Todas as mutações são Cloud Functions callable que:
1. exigem autenticação (e App Check quando habilitado);
2. validam a entrada e o papel do usuário (membro da barbearia) dentro da transação;
3. executam a regra no domínio puro;
4. gravam o agregado, a projeção pública `publicQueues/{shopId}` e os documentos auxiliares na **mesma** transação.

As Security Rules negam toda escrita do cliente e liberam leitura mínima: projeção pública para todos, agregado do dia apenas para a equipe, ticket ativo apenas para o dono.

## Consequências
- ✅ Impossível adulterar posição/ETA; uma única fonte de verdade para regras.
- ✅ Idempotência por `requestId` (UUID gerado no app) torna retries seguros.
- ⚠️ Latência de ida ao servidor nas ações → UI otimista no console do barbeiro com Desfazer.
