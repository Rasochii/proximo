import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fixtures.dart';

const _shop = 'shops/barbearia-do-ze';
const _queue = 'publicQueues/barbearia-do-ze';

Future<void> openShop(WidgetTester tester, FakeDocuments docs) async {
  await pumpProximoApp(tester, watch: docs.watch);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/b/barbearia-do-ze');
  await tester.pumpAndSettle();
}

void main() {
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
    final docs = FakeDocuments({_shop: shopJson(), _queue: {'shopId': 42}});
    addTearDown(docs.dispose);
    await openShop(tester, docs);

    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
