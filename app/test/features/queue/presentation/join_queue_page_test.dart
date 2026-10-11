import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fixtures.dart';

const _shop = 'shops/barbearia-do-ze';
const _queue = 'publicQueues/barbearia-do-ze';

Future<void> openShop(
  WidgetTester tester,
  FakeDocuments docs, {
  DateTime Function()? clock,
}) async {
  await pumpProximoApp(tester, watch: docs.watch, clock: clock);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/b/barbearia-do-ze');
  await tester.pumpAndSettle();
}

void main() {
  group('validade da fila (virada do dia)', () {
    // A fila vale até a meia-noite da barbearia; o servidor grava esse instante em `validUntil`.
    final midnight = DateTime(2026, 10, 11);

    testWidgets('a fila de ontem é tratada como ainda não aberta hoje', (tester) async {
      final docs = FakeDocuments({
        _shop: shopJson(),
        _queue: publicQueueJson(validUntil: midnight),
      });
      addTearDown(docs.dispose);
      await openShop(tester, docs, clock: () => DateTime(2026, 10, 11, 8));

      expect(find.text('A fila de hoje ainda não foi aberta.'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsNothing);
      expect(find.text('Lucas M.'), findsNothing);
    });

    testWidgets('antes do prazo a fila aparece normalmente', (tester) async {
      final docs = FakeDocuments({
        _shop: shopJson(),
        _queue: publicQueueJson(validUntil: midnight),
      });
      addTearDown(docs.dispose);
      await openShop(tester, docs, clock: () => DateTime(2026, 10, 10, 15));

      expect(find.text('2 pessoas esperando'), findsOneWidget);
    });

    testWidgets('se o dia vira com a tela aberta, a fila vencida some sozinha', (tester) async {
      var now = DateTime(2026, 10, 10, 23, 59);
      final docs = FakeDocuments({
        _shop: shopJson(),
        _queue: publicQueueJson(validUntil: midnight),
      });
      addTearDown(docs.dispose);
      await openShop(tester, docs, clock: () => now);
      expect(find.text('2 pessoas esperando'), findsOneWidget);

      now = DateTime(2026, 10, 11, 0, 0, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(find.text('A fila de hoje ainda não foi aberta.'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsNothing);
    });

    testWidgets('aparelho que dormiu a noite toda percebe a virada em até um minuto', (
      tester,
    ) async {
      // O temporizador não conta o tempo suspenso: às 15h faltavam 9 horas para o prazo, mas o
      // relógio do aparelho já diz 8h do dia seguinte quando ele acorda.
      var now = DateTime(2026, 10, 10, 15);
      final docs = FakeDocuments({
        _shop: shopJson(),
        _queue: publicQueueJson(validUntil: midnight),
      });
      addTearDown(docs.dispose);
      await openShop(tester, docs, clock: () => now);
      expect(find.text('2 pessoas esperando'), findsOneWidget);

      now = DateTime(2026, 10, 11, 8);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(find.text('A fila de hoje ainda não foi aberta.'), findsOneWidget);
    });

    testWidgets('uma fila nova, do dia seguinte, volta a aparecer', (tester) async {
      final docs = FakeDocuments({
        _shop: shopJson(),
        _queue: publicQueueJson(validUntil: midnight),
      });
      addTearDown(docs.dispose);
      await openShop(tester, docs, clock: () => DateTime(2026, 10, 11, 8));
      expect(find.text('A fila de hoje ainda não foi aberta.'), findsOneWidget);

      docs.emit(_queue, publicQueueJson(waiting: 1, validUntil: DateTime(2026, 10, 12)));
      await tester.pumpAndSettle();

      expect(find.text('1 pessoa esperando'), findsOneWidget);
    });
  });

  testWidgets('mostra a fila e atualiza em tempo real quando alguém entra', (tester) async {
    final docs = FakeDocuments({_shop: shopJson(), _queue: publicQueueJson(waiting: 1)});
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    expect(find.text('Barbearia do Zé'), findsOneWidget);
    expect(find.text('1 pessoa esperando'), findsOneWidget);
    expect(find.text('nº 1 · Ana S.'), findsOneWidget);
    expect(find.text('Lucas M.'), findsOneWidget);

    docs.emit(_queue, publicQueueJson(waiting: 3));
    await tester.pumpAndSettle();

    expect(find.text('3 pessoas esperando'), findsOneWidget);
    // A lista é preguiçosa: o 3º da fila fica abaixo da dobra na tela de teste (800×600).
    await tester.scrollUntilVisible(find.text('3º'), 200);
    expect(find.text('3º'), findsOneWidget);
  });

  testWidgets('mostra a espera de quem entrar agora como faixa', (tester) async {
    final docs = FakeDocuments({_shop: shopJson(), _queue: publicQueueJson(waiting: 1)});
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    // 55 min → ±11 min
    expect(find.text('~44–66 min'), findsOneWidget);
  });

  testWidgets('barbearia inexistente', (tester) async {
    final docs = FakeDocuments();
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    expect(find.textContaining('Barbearia não encontrada'), findsOneWidget);
  });

  testWidgets('barbearia existe mas a fila do dia ainda não abriu', (tester) async {
    final docs = FakeDocuments({_shop: shopJson()});
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    expect(find.text('A fila de hoje ainda não foi aberta.'), findsOneWidget);
  });

  testWidgets('dados inválidos viram erro com opção de tentar de novo', (tester) async {
    final docs = FakeDocuments({
      _shop: shopJson(),
      _queue: {'shopId': 42},
    });
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('barbearia inexistente oferece tentar outro código', (tester) async {
    final docs = FakeDocuments();
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    await tester.tap(find.text('Tentar outro código'));
    await tester.pumpAndSettle();

    expect(find.text('Entrar em uma fila'), findsOneWidget);
  });

  group('layout de site (tela larga)', () {
    testWidgets('atualiza ao vivo, com resumo e lista lado a lado', (tester) async {
      useWideScreen(tester);
      final docs = FakeDocuments({_shop: shopJson(), _queue: publicQueueJson(waiting: 1)});
      addTearDown(docs.dispose);
      await openShop(tester, docs);

      expect(find.text('1 pessoa esperando'), findsOneWidget);

      docs.emit(_queue, publicQueueJson(waiting: 3));
      await tester.pumpAndSettle();

      expect(find.text('3 pessoas esperando'), findsOneWidget);
      // Sem rolar: a lista fica ao lado do resumo.
      expect(find.text('3º').hitTestable(), findsOneWidget);
      final summary = tester.getRect(find.text('3 pessoas esperando'));
      final third = tester.getRect(find.text('3º'));
      expect(third.left, greaterThan(summary.right));
    });

    testWidgets('fila vazia diz isso no cartão da lista, sem repetir o resumo', (tester) async {
      useWideScreen(tester);
      final docs = FakeDocuments({_shop: shopJson(), _queue: publicQueueJson(waiting: 0)});
      addTearDown(docs.dispose);
      await openShop(tester, docs);

      expect(find.text('Ninguém esperando'), findsOneWidget);
      expect(find.text('Ninguém na fila no momento.'), findsOneWidget);
    });

    testWidgets('fila ainda não aberta continua mostrando de qual barbearia é', (tester) async {
      useWideScreen(tester);
      final docs = FakeDocuments({_shop: shopJson()});
      addTearDown(docs.dispose);
      await openShop(tester, docs);

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.text('A fila de hoje ainda não foi aberta.'), findsOneWidget);
    });

    testWidgets('no erro, o botão de tentar de novo não atravessa a página', (tester) async {
      useWideScreen(tester);
      final docs = FakeDocuments({
        _shop: shopJson(),
        _queue: {'shopId': 42},
      });
      addTearDown(docs.dispose);
      await openShop(tester, docs);

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      final button = tester.getSize(find.widgetWithText(FilledButton, 'Tentar de novo'));
      expect(button.width, lessThanOrEqualTo(560));
    });

    testWidgets('barbearia inexistente tem o cabeçalho do site e a volta ao início', (
      tester,
    ) async {
      useWideScreen(tester);
      final docs = FakeDocuments();
      addTearDown(docs.dispose);
      await openShop(tester, docs);

      expect(find.textContaining('Barbearia não encontrada'), findsOneWidget);
      await tester.tap(find.text('Tentar outro código'));
      await tester.pumpAndSettle();

      expect(find.text('Espere pelo corte onde você quiser'), findsOneWidget);
    });
  });
}
