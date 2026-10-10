# ADR 0007 — Vínculo de equipe em `staff/{uid}`

**Status:** aceito · 2026-10-10

## Contexto
Depois do login, o app do barbeiro precisa saber de qual barbearia ele faz parte. O vínculo já existe em `shops/{shopId}/members/{uid}`, mas esse caminho exige conhecer o `shopId` antes.

## Decisão
O servidor mantém um documento `staff/{uid}` com `shopId` e `role` (`owner` ou `barber`) para cada membro ativo. O app lê apenas o próprio documento; ninguém lista nem escreve pela rule. `shops/{shopId}/members/{uid}` continua sendo a fonte de verdade para autorização nas callables e nas rules; o app usa `staff/{uid}` só para navegação, nunca como permissão.

Alternativas descartadas:
- **Custom claims** (`shopId`, `role`): só valem depois que o token renova, e mudar de barbearia exigiria forçar a renovação.
- **Consulta collection group em `members`**: pede índice e rule próprios, e o documento de membro não guarda o uid como campo.

## Consequências
- ✅ Mesma forma de `activeTickets/{uid}`: leitura em tempo real e rule de uma linha.
- ✅ O convite de barbeiros (F6) e o cadastro da barbearia (F5) só precisam gravar este documento junto com o de membro.
- ⚠️ É uma cópia do vínculo: quem gravar um membro grava `staff/{uid}` na mesma transação, e quem desativar ou remover um membro (inclusive na exclusão de conta) apaga `staff/{uid}`. Até a F5, só o seed dos emuladores grava os dois.
- ⚠️ Um usuário pertence a uma única barbearia. Suportar várias exigirá mudar o formato do documento.
