import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/barber_console/presentation/shift_controller.dart';

import '../../../helpers/fake_auth.dart';
import '../../../helpers/fake_callables.dart';
import '../../../helpers/fixtures.dart';

const _shop = 'shops/barbearia-do-ze';
const _staff = 'staff/barbeiro-ze';
const _queue = 'publicQueues/barbearia-do-ze';

/// Zé como aparece na fila pública quando está em expediente.
JsonMap ze(String status, {int? servingNumber}) => {
  'id': 'barbeiro-ze',
  'displayName': 'Zé',
  'status': status,
  'servingNumber': servingNumber,
};

/// Fila com o Zé na situação pedida; o ticket em atendimento (nº 1) é de outro barbeiro.
JsonMap queueWithZe(String status, {int waiting = 2}) =>
    publicQueueJson(waiting: waiting, barbers: [ze(status)], servingBarberId: 'barbeiro-joao');

/// Fila em que o Zé está atendendo o ticket nº 1.
JsonMap queueWithZeServing() => publicQueueJson(
  barbers: [ze('available', servingNumber: 1)],
  servingBarberId: 'barbeiro-ze',
);

Future<({FakeDocuments docs, FakeCallables backend})> openConsole(
  WidgetTester tester, {
  JsonMap? queue,
  FakeCallables? backend,
  DateTime Function()? clock,
}) async {
  final docs = FakeDocuments({
    _shop: shopJson(),
    _staff: {'shopId': 'barbearia-do-ze', 'role': 'owner'},
    _queue: ?queue,
  });
  final auth = FakeAuthRepository(signedInAs: barberZe);
  final callables = backend ?? FakeCallables();
  addTearDown(docs.dispose);
  addTearDown(auth.dispose);

  await pumpProximoApp(
    tester,
    watch: docs.watch,
    invoke: callables.invoke,
    auth: auth,
    clock: clock,
  );
  // Pela rota, e não pelo botão da inicial: assim o teste não depende do layout da inicial.
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/console');
  await tester.pumpAndSettle();
  return (docs: docs, backend: callables);
}

/// Deixa passar a espera pela confirmação da fila e a pausa de segurança dos botões.
Future<void> letShiftSettle(WidgetTester tester) async {
  await tester.pump(ShiftController.confirmationTimeout);
  await tester.pump(ShiftController.settleDelay);
  await tester.pump();
}

/// "Encerrar expediente" fica no menu do cartão, a dois toques.
Future<void> tapEndShift(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Mais ações do expediente'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Encerrar expediente'));
  await tester.pump();
}

/// O botão principal do cartão de expediente (cheio ou de contorno, conforme a situação).
final mainAction = find.byKey(const ValueKey('shift-main-action'));

ButtonStyleButton mainButton(WidgetTester tester) => tester.widget<ButtonStyleButton>(mainAction);

void main() {
  group('fora do expediente', () {
    testWidgets('antes de a fila de hoje existir, oferece iniciar o expediente', (tester) async {
      await openConsole(tester);

      expect(find.text('Fora do expediente'), findsOneWidget);
      expect(find.text('Iniciar expediente'), findsOneWidget);
      // Sem expediente não há o que encerrar.
      expect(find.byTooltip('Mais ações do expediente'), findsNothing);
    });

    testWidgets('com outro barbeiro atendendo, continua fora e já vê a fila', (tester) async {
      await openConsole(tester, queue: publicQueueJson());

      expect(find.text('Fora do expediente'), findsOneWidget);
      expect(find.text('nº 1 · Ana S.'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsOneWidget);
      expect(find.text('Lucas M.'), findsOneWidget);
    });

    testWidgets('iniciar: o cartão fica ocupado até a fila confirmar o novo status', (
      tester,
    ) async {
      final (:docs, :backend) = await openConsole(tester);

      await tester.tap(find.text('Iniciar expediente'));
      await tester.pump();

      expect(backend.calls, hasLength(1));
      expect(backend.calls.single.name, 'setBarberStatus');
      expect(backend.calls.single.payload, containsPair('shopId', 'barbearia-do-ze'));
      expect(backend.calls.single.payload, containsPair('status', 'available'));
      expect(backend.calls.single.payload['requestId'], isA<String>());

      // O servidor já respondeu, mas a fila ainda não chegou: a tela não finge que mudou nem
      // libera o botão para um segundo toque.
      await tester.pump();
      expect(find.text('Fora do expediente'), findsOneWidget);
      expect(find.text('Iniciando…'), findsOneWidget);
      expect(mainButton(tester).onPressed, isNull);

      docs.emit(_queue, queueWithZe('available', waiting: 0));
      await tester.pump();
      await tester.pump();

      expect(find.text('Em expediente'), findsOneWidget);
      expect(find.text('Fazer pausa'), findsOneWidget);
      // O botão novo apareceu no mesmo lugar: fica inerte por um instante.
      expect(mainButton(tester).onPressed, isNull);

      await letShiftSettle(tester);
      expect(mainButton(tester).onPressed, isNotNull);
      expect(find.byTooltip('Mais ações do expediente'), findsOneWidget);
    });

    testWidgets('se a fila não confirmar, os botões voltam depois de um tempo', (tester) async {
      await openConsole(tester);

      await tester.tap(find.text('Iniciar expediente'));
      await tester.pump();
      await tester.pump();
      expect(mainButton(tester).onPressed, isNull);

      await letShiftSettle(tester);

      expect(find.text('Iniciar expediente'), findsOneWidget);
      expect(mainButton(tester).onPressed, isNotNull);
    });
  });

  group('em expediente', () {
    testWidgets('fila vazia diz que não há ninguém esperando', (tester) async {
      await openConsole(tester, queue: queueWithZe('available', waiting: 0));

      expect(find.text('Em expediente'), findsOneWidget);
      expect(find.text('Ninguém esperando'), findsOneWidget);
    });

    testWidgets('mostra quantos esperam, quem são e o cliente de outro barbeiro', (tester) async {
      await openConsole(tester, queue: queueWithZe('available'));

      expect(find.text('2 pessoas esperando'), findsOneWidget);
      expect(find.text('Lucas M.'), findsOneWidget);
      expect(find.text('1º'), findsOneWidget);
      expect(find.text('nº 1 · Ana S.'), findsOneWidget);
      // O ticket em atendimento é de outro barbeiro.
      expect(find.text('Atendendo agora'), findsNothing);
    });

    testWidgets('destaca no cartão o cliente que o próprio barbeiro está atendendo', (
      tester,
    ) async {
      await openConsole(tester, queue: queueWithZeServing());

      expect(find.text('Atendendo agora'), findsOneWidget);
      // Uma vez só: no cartão, sem repetir na seção dos colegas.
      expect(find.text('nº 1 · Ana S.'), findsOneWidget);
      expect(find.text('Em atendimento'), findsNothing);
    });

    testWidgets('a fila atualiza ao vivo', (tester) async {
      final (:docs, backend: _) = await openConsole(
        tester,
        queue: queueWithZe('available', waiting: 1),
      );
      expect(find.text('João'), findsNothing);

      docs.emit(_queue, queueWithZe('available'));
      await tester.pumpAndSettle();

      expect(find.text('João'), findsOneWidget);
      expect(find.text('2 pessoas esperando'), findsOneWidget);
    });

    testWidgets('fazer pausa e voltar', (tester) async {
      final (:docs, :backend) = await openConsole(tester, queue: queueWithZe('available'));

      await tester.tap(find.text('Fazer pausa'));
      await tester.pump();
      expect(backend.calls.single.payload, containsPair('status', 'paused'));
      expect(find.text('Pausando…'), findsOneWidget);

      docs.emit(_queue, queueWithZe('paused'));
      await letShiftSettle(tester);
      expect(find.text('Em pausa'), findsOneWidget);

      await tester.tap(find.text('Voltar da pausa'));
      await tester.pump();
      expect(backend.calls.last.payload, containsPair('status', 'available'));
      expect(find.text('Retomando…'), findsOneWidget);

      docs.emit(_queue, queueWithZe('available'));
      await letShiftSettle(tester);
      expect(find.text('Em expediente'), findsOneWidget);
    });

    testWidgets('encerrar fica no menu e tira o barbeiro da fila pública', (tester) async {
      final (:docs, :backend) = await openConsole(tester, queue: queueWithZe('available'));

      // Não há botão direto para encerrar: um esbarrão não encerra o expediente.
      expect(find.text('Encerrar expediente'), findsNothing);
      await tapEndShift(tester);
      expect(backend.calls.single.payload, containsPair('status', 'off'));
      expect(find.text('Encerrando…'), findsOneWidget);

      // Quem encerra sai da lista de barbeiros da fila pública.
      docs.emit(_queue, publicQueueJson(barbers: []));
      await letShiftSettle(tester);

      expect(find.text('Fora do expediente'), findsOneWidget);
    });

    testWidgets('encerrar também funciona a partir da pausa', (tester) async {
      final (:docs, :backend) = await openConsole(tester, queue: queueWithZe('paused'));

      await tapEndShift(tester);
      expect(backend.calls.single.payload, containsPair('status', 'off'));

      docs.emit(_queue, publicQueueJson(barbers: []));
      await letShiftSettle(tester);
      expect(find.text('Fora do expediente'), findsOneWidget);
    });

    testWidgets('encerrar com cliente na cadeira é recusado, e o motivo fica no cartão', (
      tester,
    ) async {
      final backend = FakeCallables(
        (name, payload) => throw FakeCallables.domainError('finish-current-first'),
      );
      await openConsole(tester, backend: backend, queue: queueWithZeServing());

      await tapEndShift(tester);
      await tester.pumpAndSettle();

      expect(find.text('Finalize o atendimento atual primeiro.'), findsOneWidget);
      expect(find.text('Em expediente'), findsOneWidget);
      // Os botões voltam a funcionar depois da recusa, e o aviso continua lá.
      expect(mainButton(tester).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Finalize o atendimento atual primeiro.'), findsOneWidget);
    });

    testWidgets('quem perdeu a permissão vê o motivo no cartão', (tester) async {
      final backend = FakeCallables(
        (name, payload) => throw const CallableException('permission-denied'),
      );
      await openConsole(tester, backend: backend, queue: queueWithZe('available'));

      await tester.tap(find.text('Fazer pausa'));
      await tester.pumpAndSettle();

      expect(find.text('Você não tem permissão para fazer isso.'), findsOneWidget);
    });

    testWidgets('durante o pedido os botões ficam desabilitados e um segundo toque não reenvia', (
      tester,
    ) async {
      final backend = FakeCallables()..gate = Completer<void>();
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );

      await tester.tap(find.text('Fazer pausa'));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(mainButton(tester).onPressed, isNull);
      await tester.tap(mainAction, warnIfMissed: false);
      await tester.pump();
      expect(backend.calls, hasLength(1));

      backend.gate!.complete();
      docs.emit(_queue, queueWithZe('paused'));
      await letShiftSettle(tester);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Em pausa'), findsOneWidget);
    });

    testWidgets('sair da conta no meio de um pedido não quebra nada', (tester) async {
      final backend = FakeCallables()..gate = Completer<void>();
      await openConsole(tester, backend: backend, queue: queueWithZe('available'));

      await tester.tap(find.text('Fazer pausa'));
      await tester.pump();
      // A barra de progresso não para de animar: avança o tempo em vez de esperar assentar.
      await tester.tap(find.byTooltip('Conta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Sair'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Entrar como barbeiro'), findsOneWidget);

      backend.gate!.complete();
      await letShiftSettle(tester);

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('enquanto a fila não chega, mostra que está carregando', (tester) async {
    final docs = FakeDocuments({
      _shop: shopJson(),
      _staff: {'shopId': 'barbearia-do-ze', 'role': 'owner'},
    });
    final auth = FakeAuthRepository(signedInAs: barberZe);
    final never = StreamController<JsonMap?>();
    addTearDown(docs.dispose);
    addTearDown(auth.dispose);
    addTearDown(never.close);

    await pumpProximoApp(
      tester,
      watch: (path) => path == _queue ? never.stream : docs.watch(path),
      auth: auth,
    );
    await tester.tap(find.text('Sou barbeiro'));
    // O indicador gira sem parar: avança o tempo em vez de esperar a tela assentar.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Fora do expediente'), findsNothing);
  });

  testWidgets('quem não encerrou ontem começa hoje fora do expediente, sem a fila de ontem', (
    tester,
  ) async {
    // A fila pública de ontem ainda diz que o Zé está em expediente, com duas pessoas esperando.
    final yesterday = {...queueWithZe('available')};
    yesterday['validUntil'] = DateTime(2026, 10, 11).millisecondsSinceEpoch;
    await openConsole(tester, queue: yesterday, clock: () => DateTime(2026, 10, 11, 8));

    expect(find.text('Fora do expediente'), findsOneWidget);
    expect(find.text('Iniciar expediente'), findsOneWidget);
    expect(find.text('Lucas M.'), findsNothing);
  });

  testWidgets('erro ao ler a fila oferece tentar de novo', (tester) async {
    final (:docs, backend: _) = await openConsole(tester, queue: queueWithZe('available'));

    docs.fail(_queue, Exception('indisponível'));
    await tester.pumpAndSettle();

    expect(find.text('Algo deu errado. Tente de novo em instantes.'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('Em expediente'), findsOneWidget);
  });

  testWidgets('em tela larga o console continua utilizável', (tester) async {
    useWideScreen(tester);
    await openConsole(tester, queue: queueWithZe('available'));

    expect(find.text('Em expediente'), findsOneWidget);
    expect(find.text('Lucas M.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('celular estreito com letra em dobro: nada estoura nas três situações', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final (:docs, backend: _) = await openConsole(tester);
    expect(find.text('Fora do expediente'), findsOneWidget);
    expect(tester.takeException(), isNull);

    docs.emit(_queue, queueWithZeServing());
    await tester.pumpAndSettle();
    expect(find.text('Em expediente'), findsOneWidget);
    expect(tester.takeException(), isNull);

    docs.emit(_queue, queueWithZe('paused'));
    await tester.pumpAndSettle();
    expect(find.text('Em pausa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
