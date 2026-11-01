import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/features/barber_console/presentation/shop_console_view.dart';

import '../../../helpers/console_harness.dart';
import '../../../helpers/fake_callables.dart';
import '../../../helpers/fixtures.dart';
import '../../../helpers/real_font.dart';

void main() {
  setUpAll(loadRoboto);

  final bigButton = find.byKey(const ValueKey('console-main-action'));
  final failureIcon = find.byIcon(Icons.error_outline_rounded);
  final actionBar = find.byType(ShopConsoleActionBar);
  const longLabel = 'Maximiliano C.';

  /// "Próximo!" aceito: alguém na cadeira, outra pessoa esperando e o aviso de Desfazer na tela.
  Future<void> advance(WidgetTester tester, {required FakeCallables backend}) async {
    final (:docs, backend: _) = await openConsole(
      tester,
      backend: backend,
      queue: queueWithZe('available'),
    );
    await tester.tap(bigButton);
    await tester.pump();
    docs.emit(
      consoleQueue,
      publicQueueJson(
        waiting: 1,
        barbers: [ze('available', servingNumber: 7)],
        nowServing: [
          {'ticketId': 't7', 'number': 7, 'label': longLabel, 'barberId': 'barbeiro-ze'},
        ],
      ),
    );
    await letShiftSettle(tester);
  }

  /// Aceita o primeiro avanço e recusa os seguintes.
  FakeCallables refusingAfterFirst() {
    var calls = 0;
    return FakeCallables((name, payload) {
      if (++calls > 1) throw FakeCallables.domainError('rate-limited');
      return {
        'finished': null,
        'called': {'ticketId': 't7', 'number': 7, 'label': longLabel},
      };
    });
  }

  for (final (size, scale) in const [
    (Size(360, 640), 2.0),
    (Size(800, 360), 1.0),
    (Size(844, 390), 1.0),
    (Size(640, 360), 1.5),
    (Size(844, 390), 2.0),
  ]) {
    testWidgets('em ${size.width}×${size.height} com letra $scale, tudo cabe junto', (
      tester,
    ) async {
      useLargeText(tester, size: size, scale: scale);
      await advance(tester, backend: refusingAfterFirst());

      await tester.tap(bigButton);
      await tester.pumpAndSettle();

      // Aviso de Desfazer fora da tela estoura como exceção no Scaffold.
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('Desfazer')).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(bigButton).bottom, lessThanOrEqualTo(size.height));
      final bar = tester.getRect(actionBar);
      expect(tester.getRect(failureIcon).top, greaterThanOrEqualTo(bar.top));
      expect(tester.getRect(find.byTooltip('Dispensar aviso')).top, greaterThanOrEqualTo(bar.top));
    });
  }

  for (final (size, safeBottom) in const [
    (Size(640, 360), 0.0),
    (Size(568, 320), 0.0),
    (Size(844, 390), 21.0),
    (Size(800, 360), 24.0),
    (Size(640, 360), 24.0),
    (Size(568, 320), 21.0),
  ]) {
    testWidgets(
      'em ${size.width}×${size.height} com letra em dobro e área segura de $safeBottom, '
      'o essencial fica à vista',
      (tester) async {
        useLargeText(tester, size: size, safeBottom: safeBottom);
        await advance(tester, backend: refusingAfterFirst());

        await tester.tap(bigButton);
        await tester.pumpAndSettle();

        expect(failureIcon, findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tester.getRect(find.text('Desfazer')).top, greaterThanOrEqualTo(0));
        expect(tester.getRect(bigButton).bottom, lessThanOrEqualTo(size.height - safeBottom));
      },
    );
  }

  testWidgets('sem motivo de recusa, a barra deixa espaço para o aviso de Desfazer', (
    tester,
  ) async {
    const size = Size(568, 320);
    useLargeText(tester, size: size);
    await advance(tester, backend: refusingAfterFirst());

    expect(tester.takeException(), isNull);
    expect(tester.getRect(actionBar).height, lessThanOrEqualTo(size.height * 0.6));
  });

  testWidgets('sem botões na barra, a recusa ocupa pouco da tela e mostra que há mais texto', (
    tester,
  ) async {
    useLargeText(tester);
    final backend = FakeCallables((name, payload) => throw const CallableException('internal'));
    await openConsole(
      tester,
      backend: backend,
      queue: publicQueueJson(barbers: [], nowServing: []),
    );

    final remove = find.byTooltip('Remover nº 2 · Lucas M. da fila');
    await tester.scrollUntilVisible(remove, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(actionBar).height, lessThan(640 * 0.3));
    final hint = find.descendant(of: actionBar, matching: find.byType(RawScrollbar));
    expect(tester.widget<RawScrollbar>(hint).thumbVisibility, isTrue);
  });

  testWidgets('a recusa no cartão aparece mesmo se nascer abaixo da área visível', (tester) async {
    const size = Size(640, 360);
    useLargeText(tester, size: size);
    final backend = FakeCallables(
      (name, payload) => throw const CallableException('permission-denied'),
    );
    await openConsole(tester, backend: backend);

    await tester.tap(find.text('Iniciar expediente'));
    await tester.pumpAndSettle();

    expect(tester.getRect(failureIcon).bottom, lessThanOrEqualTo(size.height));
  });

  testWidgets('deitado, o diálogo de remoção não corta o alerta', (tester) async {
    useLargeText(tester, size: const Size(640, 360));
    await openConsole(tester, queue: queueWithZe('available'));

    final remove = find.byTooltip('Remover nº 2 · Lucas M. da fila');
    await tester.scrollUntilVisible(remove, 100, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('A pessoa perde o lugar. Não dá para desfazer.'), findsOneWidget);
  });
}
