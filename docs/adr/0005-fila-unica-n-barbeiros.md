# ADR 0005 — Fila única atendida por N barbeiros desde o domínio

**Status:** aceito · 2026-10-10

## Contexto
O MVP começa com um barbeiro, mas suportar vários barbeiros logo em seguida é requisito.

## Decisão
O domínio modela a fila como **uma fila por barbearia** com uma lista de barbeiros do dia. `callNext(barberId)` chama o primeiro ticket compatível (sem preferência ou com preferência por aquele barbeiro). O ETA é calculado por **simulação de eventos**: o barbeiro que fica livre primeiro pega o próximo ticket compatível, respeitando os intervalos do horário de funcionamento.

## Consequências
- ✅ Um barbeiro é só o caso N=1; F6 vira trabalho de UI e convites.
- ✅ A simulação usa a mesma regra de escolha do `callNext`, então ETA e realidade não divergem por construção.
- ⚠️ Preferência por barbeiro pode deixar um ticket sem previsão quando aquele barbeiro não está ativo (ETA `null`, exibido como "aguardando barbeiro").
