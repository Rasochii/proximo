# ADR 0002 — Riverpod 3 para estado e injeção de dependência

**Status:** aceito · 2026-10-10

## Contexto
O estado central do app é um stream (a fila) mais comandos assíncronos (entrar, chamar próximo). Projeto mantido por uma pessoa.

## Decisão
Riverpod 3 com providers escritos à mão (sem `riverpod_generator` por enquanto, para manter o build sem etapa de geração de código). Providers fazem a DI (portas do backend → repositórios → notifiers). `AsyncValue` representa carregando/erro/dados.

As camadas de dados dependem de **portas** (`DocumentWatcher`, `CallableInvoker`), não dos SDKs do Firebase: em testes basta sobrescrever esses providers.

## Consequências
- Reavaliar a geração de código quando surgirem Notifiers com muitos parâmetros.
- ✅ Menos boilerplate que Bloc; streams e cache resolvidos pelo framework; testes com `ProviderContainer` e overrides.
- ⚠️ Disciplina necessária para não colocar regra de negócio em providers: regra fica em use cases/entidades do domínio.
- Alternativa: Bloc/Cubit (mais explícito, preferível com time grande).
