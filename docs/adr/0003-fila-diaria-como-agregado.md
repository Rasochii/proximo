# ADR 0003 — A fila do dia é um agregado em um único documento

**Status:** aceito · 2026-10-10

## Contexto
Entrar na fila e chamar o próximo precisam ser atômicos (números únicos, nada chamado duas vezes). Uma barbearia tem dezenas, no máximo poucas centenas, de clientes por dia.

## Decisão
`shops/{shopId}/days/{yyyy-MM-dd}` guarda **todos** os tickets do dia, o estado dos barbeiros do dia, o último comando desfazível por barbeiro e os `requestId` já processados. Toda mutação é uma transação que lê e grava esse documento (mais a projeção pública e documentos auxiliares).

## Consequências
- ✅ Consistência trivial; regras de negócio ficam em funções puras testáveis sobre um objeto.
- ✅ Uma leitura entrega a fila inteira ao barbeiro.
- ⚠️ Limite de 1 MiB por documento → `maxTicketsPerDay` (padrão 200) mantém o documento abaixo de ~100 KB.
- ⚠️ ~1 escrita/s sustentada por documento → muito acima do ritmo real de uma barbearia.
- Métricas históricas, quando necessárias, serão derivadas por um trigger para uma coleção própria.
