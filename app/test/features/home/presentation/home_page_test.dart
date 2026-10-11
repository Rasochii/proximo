import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/widgets/site_shell.dart';

import '../../../helpers/fixtures.dart';

FakeDocuments seededDocs() => FakeDocuments({
  'shops/barbearia-do-ze': shopJson(),
  'publicQueues/barbearia-do-ze': publicQueueJson(),
});

Future<void> pumpHome(WidgetTester tester) async {
  final docs = seededDocs();
  addTearDown(docs.dispose);
  await pumpProximoApp(tester, watch: docs.watch);
}

void main() {
  group('layout de site (tela larga)', () {
    testWidgets('apresenta o produto: chamada, exemplo de fila e como funciona', (tester) async {
      useWideScreen(tester);
      await pumpHome(tester);

      expect(find.text('Espere pelo corte onde você quiser'), findsOneWidget);
      expect(find.text('Exemplo de fila'), findsOneWidget);
      expect(find.text('Abra a fila da barbearia'), findsOneWidget);
      expect(find.text('Veja o movimento e entre'), findsOneWidget);
      expect(find.text('Chegue na sua vez'), findsOneWidget);
      // O cartão "Entrar em uma fila" é do layout de celular.
      expect(find.text('Entrar em uma fila'), findsNothing);

      // O rodapé fica no fim da rolagem.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Próximo! · fila virtual para barbearias'), findsOneWidget);
    });

    testWidgets('a fila de exemplo é uma ilustração só para o leitor de tela', (tester) async {
      useWideScreen(tester);
      final semantics = tester.ensureSemantics();
      await pumpHome(tester);

      expect(find.bySemanticsLabel(RegExp('^Ilustração: exemplo de fila')), findsOneWidget);
      // Os nomes do exemplo aparecem na tela, mas não como itens soltos de uma fila real.
      expect(find.text('Lucas M.'), findsOneWidget);
      expect(find.bySemanticsLabel('Lucas M.'), findsNothing);
      semantics.dispose();
    });

    testWidgets('o código da barbearia abre a fila dela em duas colunas', (tester) async {
      useWideScreen(tester);
      await pumpHome(tester);

      await tester.enterText(find.byType(TextField), '  Barbearia-do-Ze ');
      await tester.tap(find.widgetWithText(FilledButton, 'Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsOneWidget);
      // Sem rolar: resumo e lista cabem lado a lado.
      expect(find.text('2º').hitTestable(), findsOneWidget);
      expect(find.text('Exemplo de fila'), findsNothing);

      // Página curta: o rodapé encosta no fim da janela e ocupa só a própria altura.
      final footer = tester.getRect(find.byType(SiteFooter));
      expect(footer.bottom, 800);
      expect(footer.height, lessThan(100));
    });

    testWidgets('"Sou barbeiro" no cabeçalho leva ao login, num cartão', (tester) async {
      useWideScreen(tester);
      await pumpHome(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Sou barbeiro'));
      await tester.pumpAndSettle();

      expect(find.text('Entrar como barbeiro'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Entrar como barbeiro'), matching: find.byType(Card)),
        findsOneWidget,
      );
      // A marca no cabeçalho volta para o início.
      await tester.tap(find.byTooltip('Voltar ao início'));
      await tester.pumpAndSettle();
      expect(find.text('Espere pelo corte onde você quiser'), findsOneWidget);
    });

    testWidgets('"Como funciona" no cabeçalho rola até a seção', (tester) async {
      useWideScreen(tester);
      // Janela baixa: a seção começa fora da área visível.
      tester.view.physicalSize = const Size(1280, 500);
      await pumpHome(tester);
      expect(find.text('Abra a fila da barbearia').hitTestable(), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Como funciona'));
      await tester.pumpAndSettle();

      expect(find.text('Abra a fila da barbearia').hitTestable(), findsOneWidget);
    });

    testWidgets('o que foi digitado continua no campo quando a janela estreita', (tester) async {
      useWideScreen(tester);
      await pumpHome(tester);
      await tester.enterText(find.byType(TextField), 'barbearia-do');

      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();

      expect(find.text('Entrar em uma fila'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'barbearia-do');
    });

    testWidgets('com letra em dobro, uma janela de 1800 px comporta o layout sem estourar', (
      tester,
    ) async {
      useWideScreen(tester);
      tester.view.physicalSize = const Size(1800, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester);

      expect(find.text('Espere pelo corte onde você quiser'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Com a letra em dobro o botão pode ficar abaixo da dobra: rola até ele antes de tocar.
      await tester.enterText(find.byType(TextField), 'barbearia-do-ze');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Ver fila'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ver fila'));
      await tester.pumpAndSettle();
      expect(find.text('2 pessoas esperando'), findsOneWidget);
      expect(tester.takeException(), isNull);

      GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/console');
      await tester.pumpAndSettle();
      expect(find.text('Entrar como barbeiro'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('com letra em dobro, 1280 px volta a ser coluna única', (tester) async {
      useWideScreen(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHome(tester);

      expect(find.text('Entrar em uma fila'), findsOneWidget);
      expect(find.text('Espere pelo corte onde você quiser'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('campo do código da barbearia', () {
    testWidgets('explica o que é o código', (tester) async {
      await pumpHome(tester);

      expect(find.textContaining('É o final do link da barbearia'), findsOneWidget);
      expect(find.text('Código da barbearia'), findsOneWidget);
    });

    testWidgets('vazio: avisa no campo e não sai da tela', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Digite o código da barbearia.'), findsOneWidget);
      expect(find.text('Entrar em uma fila'), findsOneWidget);
    });

    testWidgets('inválido: avisa no campo, e o aviso some ao corrigir', (tester) async {
      await pumpHome(tester);

      await tester.enterText(find.byType(TextField), 'Barbearia do Zé!');
      await tester.tap(find.widgetWithText(FilledButton, 'Ver fila'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Código inválido.'), findsOneWidget);
      expect(find.text('Página não encontrada'), findsNothing);

      await tester.enterText(find.byType(TextField), 'barbearia-do-ze');
      await tester.pump();
      expect(find.textContaining('Código inválido.'), findsNothing);
    });

    testWidgets('aceita o link inteiro da fila colado no campo', (tester) async {
      await pumpHome(tester);

      await tester.enterText(find.byType(TextField), 'https://proximo.app/b/barbearia-do-ze');
      await tester.tap(find.widgetWithText(FilledButton, 'Ver fila'));
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsOneWidget);
    });
  });

  testWidgets('no celular continua a coluna única, sem a página de apresentação', (tester) async {
    await pumpHome(tester);

    expect(find.text('Entrar em uma fila'), findsOneWidget);
    expect(find.text('Espere pelo corte onde você quiser'), findsNothing);
    expect(find.text('Exemplo de fila'), findsNothing);
  });
}
