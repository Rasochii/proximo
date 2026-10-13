import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/barber_console/presentation/console_controller.dart';
import 'package:proximo/features/barber_console/presentation/shop_console_view.dart';

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
  await tester.pump(ConsoleController.confirmationTimeout);
  await tester.pump(ConsoleController.settleDelay);
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

    testWidgets('sem a barra de ação, o motivo da recusa fica no cartão', (tester) async {
      final backend = FakeCallables(
        (name, payload) => throw const CallableException('permission-denied'),
      );
      await openConsole(tester, backend: backend);

      await tester.tap(find.text('Iniciar expediente'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('console-main-action')), findsNothing);
      expect(find.text('Você não tem permissão para fazer isso.'), findsOneWidget);
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

    testWidgets('encerrar com cliente na cadeira é recusado, e o motivo fica à vista', (
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

    testWidgets('quem perdeu a permissão vê o motivo', (tester) async {
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

  group('barra de ação ("Próximo!")', () {
    final bigButton = find.byKey(const ValueKey('console-main-action'));
    FilledButton big(WidgetTester tester) => tester.widget<FilledButton>(bigButton);

    /// Zé atendendo o ticket nº 2 (Lucas M.), com a fila vazia atrás dele.
    JsonMap zeServingLucas({int version = 7}) => publicQueueJson(
      waiting: 0,
      version: version,
      barbers: [ze('available', servingNumber: 2)],
      nowServing: [
        {'ticketId': 't2', 'number': 2, 'label': 'Lucas M.', 'barberId': 'barbeiro-ze'},
      ],
    );

    /// Zé atendendo o ticket nº 1 (Ana S.), sem ninguém esperando.
    JsonMap zeServingAnaAlone({String status = 'available'}) => publicQueueJson(
      waiting: 0,
      barbers: [ze(status, servingNumber: 1)],
      servingBarberId: 'barbeiro-ze',
    );

    JsonMap calledLucas({JsonMap? finished}) => {
      'finished': finished,
      'called': {'ticketId': 't2', 'number': 2, 'label': 'Lucas M.'},
    };

    testWidgets('fora do expediente não existe', (tester) async {
      await openConsole(tester, queue: publicQueueJson());

      expect(bigButton, findsNothing);
    });

    testWidgets('diz quem será chamado antes do toque', (tester) async {
      await openConsole(tester, queue: queueWithZe('available'));

      expect(find.text('Próximo!'), findsOneWidget);
      expect(find.text('Chamar nº 2 · Lucas M.'), findsOneWidget);
      // Ninguém na cadeira deste barbeiro: não há quem "não veio".
      expect(find.text('Não veio'), findsNothing);
    });

    testWidgets('chama, avisa quem foi chamado e deixa desfazer', (tester) async {
      final backend = FakeCallables(
        (name, payload) => name == 'callNext' ? calledLucas() : null,
      );
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );

      await tester.tap(bigButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(backend.calls.single.name, 'callNext');
      expect(backend.calls.single.payload, containsPair('outcome', 'done'));
      expect(find.text('Chamado: nº 2 · Lucas M.'), findsOneWidget);
      expect(find.text('Desfazer'), findsOneWidget);
      // Até a fila confirmar, um segundo toque não chama mais ninguém.
      expect(big(tester).onPressed, isNull);

      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);
      expect(find.text('Atendendo agora'), findsOneWidget);
      expect(find.text('nº 2 · Lucas M.'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(backend.calls.last.name, 'undoLast');
      expect(find.text('Chamado: nº 2 · Lucas M.'), findsNothing);

      docs.emit(_queue, {...queueWithZe('available'), 'version': 8});
      await letShiftSettle(tester);
      expect(find.text('Chamar nº 2 · Lucas M.'), findsOneWidget);
    });

    testWidgets('toque duplo chama uma pessoa só', (tester) async {
      final backend = FakeCallables((name, payload) => calledLucas())..gate = Completer<void>();
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );

      await tester.tap(bigButton);
      await tester.pump();
      expect(find.text('Chamando…'), findsOneWidget);
      await tester.tap(bigButton, warnIfMissed: false);
      await tester.pump();

      expect(backend.calls, hasLength(1));

      backend.gate!.complete();
      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);
    });

    testWidgets('"Não veio" com gente esperando chama o seguinte', (tester) async {
      final backend = FakeCallables(
        (name, payload) => calledLucas(finished: {'ticketId': 't1', 'outcome': 'no_show'}),
      );
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZeServing(),
      );

      await tester.tap(find.text('Não veio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(backend.calls.single.name, 'callNext');
      expect(backend.calls.single.payload, containsPair('outcome', 'no_show'));
      // Diferente do aviso do "Próximo!": quem esbarrou no botão errado percebe.
      expect(find.text('Anterior não veio. Chamado: nº 2 · Lucas M.'), findsOneWidget);

      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);
    });

    testWidgets('"Não veio" sem ninguém esperando só libera a cadeira', (tester) async {
      final backend = FakeCallables(
        (name, payload) => {
          'finished': {'ticketId': 't1', 'outcome': 'no_show'},
          'called': null,
        },
      );
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: zeServingAnaAlone(),
      );

      await tester.tap(find.text('Não veio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(backend.calls.single.name, 'finishCurrent');
      expect(backend.calls.single.payload, containsPair('outcome', 'no_show'));
      expect(find.text('Marcado como não veio.'), findsOneWidget);

      docs.emit(_queue, queueWithZe('available', waiting: 0));
      await letShiftSettle(tester);
    });

    testWidgets('sem ninguém esperando, o botão finaliza o atendimento atual', (tester) async {
      final backend = FakeCallables(
        (name, payload) => {
          'finished': {'ticketId': 't1', 'outcome': 'done'},
          'called': null,
        },
      );
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: zeServingAnaAlone(),
      );
      expect(find.text('Finalizar atendimento'), findsOneWidget);
      expect(find.text('Próximo!'), findsNothing);

      await tester.tap(bigButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(backend.calls.single.name, 'finishCurrent');
      expect(backend.calls.single.payload, containsPair('outcome', 'done'));
      expect(find.text('Atendimento finalizado.'), findsOneWidget);

      docs.emit(_queue, queueWithZe('available', waiting: 0));
      await letShiftSettle(tester);
    });

    testWidgets('fila vazia e cadeira vazia: botão inerte dizendo que não há quem chamar', (
      tester,
    ) async {
      await openConsole(tester, queue: queueWithZe('available', waiting: 0));

      expect(find.text('Ninguém para chamar'), findsOneWidget);
      expect(big(tester).onPressed, isNull);
    });

    testWidgets('quem espera por outro barbeiro não é oferecido para chamar', (tester) async {
      final queue = queueWithZe('available', waiting: 1);
      (queue['waiting']! as List<JsonMap>).single['preferredBarberId'] = 'barbeiro-joao';
      await openConsole(tester, queue: queue);

      expect(find.text('1 pessoa esperando'), findsOneWidget);
      expect(find.text('Ninguém para chamar'), findsOneWidget);
      expect(big(tester).onPressed, isNull);
    });

    testWidgets('"Não veio" diz ao leitor de tela quem está na cadeira', (tester) async {
      await openConsole(tester, queue: queueWithZeServing());

      expect(find.bySemanticsLabel('Não veio: nº 1 · Ana S.'), findsOneWidget);
    });

    testWidgets('em pausa, termina quem está na cadeira mas não chama mais ninguém', (
      tester,
    ) async {
      await openConsole(
        tester,
        queue: publicQueueJson(
          barbers: [ze('paused', servingNumber: 1)],
          servingBarberId: 'barbeiro-ze',
        ),
      );

      expect(find.text('Finalizar atendimento'), findsOneWidget);
      expect(find.text('Próximo!'), findsNothing);
      expect(find.text('Não veio'), findsOneWidget);
    });

    testWidgets('em pausa e sem cliente, a barra some', (tester) async {
      await openConsole(tester, queue: queueWithZe('paused'));

      expect(bigButton, findsNothing);
    });

    testWidgets('pedido recusado mostra o motivo na barra, junto do botão', (tester) async {
      final backend = FakeCallables(
        (name, payload) => throw FakeCallables.domainError('barber-not-available'),
      );
      await openConsole(tester, backend: backend, queue: queueWithZe('available'));

      await tester.tap(bigButton);
      await tester.pumpAndSettle();

      // Na barra, e só nela: fica à vista mesmo com a lista rolada, sem repetir no cartão.
      expect(find.text('Seu expediente está pausado.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ShopConsoleActionBar),
          matching: find.text('Seu expediente está pausado.'),
        ),
        findsOneWidget,
      );
      expect(find.text('Desfazer'), findsNothing);
      expect(big(tester).onPressed, isNotNull);
    });

    testWidgets('o aviso some quando acaba o prazo de desfazer', (tester) async {
      final backend = FakeCallables((name, payload) => calledLucas());
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );
      await tester.tap(bigButton);
      await tester.pump();
      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);
      expect(find.text('Desfazer'), findsOneWidget);

      await tester.pump(ConsoleController.undoWindow);
      await tester.pumpAndSettle();

      expect(find.text('Desfazer'), findsNothing);
      expect(find.text('Chamado: nº 2 · Lucas M.'), findsNothing);
    });

    testWidgets('"Desfazer" tocado na hora, antes de a fila confirmar, é enviado', (tester) async {
      final backend = FakeCallables(
        (name, payload) => name == 'callNext' ? calledLucas() : null,
      );
      await openConsole(tester, backend: backend, queue: queueWithZe('available'));

      await tester.tap(bigButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // A fila ainda não confirmou o chamado: os botões estão inertes, mas o Desfazer não.
      expect(big(tester).onPressed, isNull);

      await tester.tap(find.text('Desfazer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(backend.calls.map((call) => call.name), ['callNext', 'undoLast']);
      expect(find.text('Desfazer'), findsNothing);
      await letShiftSettle(tester);
    });

    testWidgets('desfazer que falha por falta de rede volta a ser oferecido', (tester) async {
      final backend = FakeCallables(
        (name, payload) =>
            name == 'callNext' ? calledLucas() : throw const CallableException('unavailable'),
      );
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );
      await tester.tap(bigButton);
      await tester.pump();
      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);

      await tester.tap(find.text('Desfazer'));
      // Três tentativas com espera entre elas, e depois o aviso volta.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Sem conexão com o servidor. Verifique a internet.'), findsOneWidget);
      expect(find.text('Desfazer'), findsOneWidget);
      expect(find.text('Chamado: nº 2 · Lucas M.'), findsOneWidget);
    });

    testWidgets('sair do console pela rota leva o aviso embora', (tester) async {
      final backend = FakeCallables((name, payload) => calledLucas());
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );
      await tester.tap(bigButton);
      await tester.pump();
      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);
      expect(find.text('Desfazer'), findsOneWidget);

      // No navegador, é o botão Voltar.
      GoRouter.of(tester.element(find.byType(ShopConsoleView))).go('/');
      await tester.pumpAndSettle();

      expect(find.byType(ShopConsoleView), findsNothing);
      expect(find.text('Desfazer'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sair da conta leva o aviso embora', (tester) async {
      final backend = FakeCallables((name, payload) => calledLucas());
      final (:docs, backend: _) = await openConsole(
        tester,
        backend: backend,
        queue: queueWithZe('available'),
      );
      await tester.tap(bigButton);
      await tester.pump();
      docs.emit(_queue, zeServingLucas());
      await letShiftSettle(tester);
      expect(find.text('Desfazer'), findsOneWidget);

      await tester.tap(find.byTooltip('Conta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();

      expect(find.text('Entrar como barbeiro'), findsOneWidget);
      expect(find.text('Desfazer'), findsNothing);
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
    // Sem a fila em dia, o botão não promete chamar quem pode não ser mais o próximo.
    expect(find.text('Próximo!'), findsNothing);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(find.text('Em expediente'), findsOneWidget);
    expect(find.text('Próximo!'), findsOneWidget);
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
