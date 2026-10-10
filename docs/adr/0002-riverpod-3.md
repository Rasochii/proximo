# ADR 0002 — Riverpod 3 para estado e injeção de dependência

**Status:** aceito · 2026-10-10

## Contexto
O estado central do app é um stream (a fila) mais comandos assíncronos (entrar, chamar próximo). Projeto mantido por uma pessoa.

## Decisão
Riverpod 3 com `riverpod_generator`. Providers fazem a DI (datasources → repositórios → use cases → notifiers). `AsyncValue` representa carregando/erro/dados.

## Consequências
- ✅ Menos boilerplate que Bloc; streams e cache resolvidos pelo framework; testes com `ProviderContainer` e overrides.
- ⚠️ Disciplina necessária para não colocar regra de negócio em providers: regra fica em use cases/entidades do domínio.
- Alternativa: Bloc/Cubit (mais explícito, preferível com time grande).
