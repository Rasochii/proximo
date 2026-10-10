import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/app.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: ProximoApp()));
  await tester.pumpAndSettle();
}

void main() {
  group('ProximoApp', () {
    testWidgets('abre na tela inicial com as duas jornadas', (tester) async {
      await pumpApp(tester);

      expect(find.text('Próximo!'), findsOneWidget);
      expect(find.text('Entrar em uma fila'), findsOneWidget);
      expect(find.text('Sou barbeiro'), findsOneWidget);
    });

    testWidgets('código da barbearia leva para a fila dela', (tester) async {
      await pumpApp(tester);

      await tester.enterText(find.byType(TextField), '  Barbearia-do-Ze ');
      await tester.tap(find.text('Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Fila de barbearia-do-ze'), findsOneWidget);
    });

    testWidgets('código inválido cai na página de não encontrado', (tester) async {
      await pumpApp(tester);

      await tester.enterText(find.byType(TextField), 'código inválido!');
      await tester.tap(find.text('Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Página não encontrada'), findsOneWidget);
    });
  });
}
