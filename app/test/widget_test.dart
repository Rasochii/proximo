import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fixtures.dart';

void main() {
  group('ProximoApp', () {
    testWidgets('abre na tela inicial com as duas jornadas', (tester) async {
      await pumpProximoApp(tester, watch: FakeDocuments().watch);

      expect(find.text('Próximo!'), findsOneWidget);
      expect(find.text('Entrar em uma fila'), findsOneWidget);
      expect(find.text('Sou barbeiro'), findsOneWidget);
    });

    testWidgets('código da barbearia leva para a fila dela', (tester) async {
      final docs = FakeDocuments({
        'shops/barbearia-do-ze': shopJson(),
        'publicQueues/barbearia-do-ze': publicQueueJson(),
      });
      await pumpProximoApp(tester, watch: docs.watch);

      await tester.enterText(find.byType(TextField), '  Barbearia-do-Ze ');
      await tester.tap(find.text('Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsOneWidget);
    });

    testWidgets('código inválido cai na página de não encontrado', (tester) async {
      await pumpProximoApp(tester, watch: FakeDocuments().watch);

      await tester.enterText(find.byType(TextField), 'código inválido!');
      await tester.tap(find.text('Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Página não encontrada'), findsOneWidget);
    });
  });
}
