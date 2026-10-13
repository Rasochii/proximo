import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/config/clock.dart';
import 'package:proximo/core/config/provider_retry.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/barber_console/presentation/console_controller.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

import '../../../helpers/fake_callables.dart';
import '../../../helpers/fixtures.dart';

const _queue = 'publicQueues/barbearia-do-ze';
const _me = 'barbeiro-ze';
const ConsoleKey _key = (shopId: 'barbearia-do-ze', barberId: _me);

/// Fila pública com o barbeiro do teste na situação pedida, atendendo [serving] (se houver).
JsonMap queueWith(String status, {JsonMap? serving, int version = 7}) => publicQueueJson(
  version: version,
  barbers: [
    {'id': _me, 'displayName': 'Zé', 'status': status, 'servingNumber': serving?['number']},
  ],
  nowServing: [?serving],
);

/// Ticket nº 2 na cadeira do barbeiro do teste.
JsonMap lucasServed() => {'ticketId': 't2', 'number': 2, 'label': 'Lucas M.', 'barberId': _me};

/// Resposta do servidor a um "Próximo!" que chamou o ticket nº 2.
JsonMap calledLucas({JsonMap? finished}) => {
  'finished': finished,
  'called': {'ticketId': 't2', 'number': 2, 'label': 'Lucas M.'},
};

// `testWidgets` dá um relógio falso: o tempo só anda com `tester.pump`, e os temporizadores do
// controller podem ser testados sem esperar de verdade.
void main() {
  late FakeDocuments docs;
  late FakeCallables backend;
  late ProviderContainer container;

  // Chamado dentro de cada teste, e não num setUp: o que é criado fora do corpo do teste fica
  // fora do relógio falso, e os temporizadores disparados pela fila rodariam em tempo real.
  void arrange({JsonMap? queue}) {
    docs = FakeDocuments({_queue: ?queue});
    backend = FakeCallables();
    addTearDown(docs.dispose);
    container = ProviderContainer.test(
      retry: noAutomaticRetry,
      overrides: [
        documentWatcherProvider.overrideWithValue(docs.watch),
        callableInvokerProvider.overrideWithValue(backend.invoke),
        // O relógio do app anda junto com o tempo do teste (`tester.pump`), como os temporizadores.
        clockProvider.overrideWithValue(() => TestWidgetsFlutterBinding.instance.clock.now()),
      ],
    )..listen(consoleControllerProvider(_key), (_, _) {});
  }

  ConsoleState state() => container.read(consoleControllerProvider(_key));
  ConsoleController controller() => container.read(consoleControllerProvider(_key).notifier);

  // Um avanço aceito deixa o temporizador do prazo de desfazer correndo. O container é
  // descartado no fim do corpo de cada teste, antes de o flutter_test conferir se sobrou
  // temporizador (o descarte automático do `ProviderContainer.test` só vem depois disso).
  void testConsole(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      container.dispose();
    });
  }

  Future<void> letSettle(WidgetTester tester) async {
    await tester.pump(ConsoleController.confirmationTimeout);
    await tester.pump(ConsoleController.settleDelay);
  }

  group('expediente', () {
    testConsole('pedido aceito fica em aberto até a fila mostrar o status pedido', (tester) async {
      arrange();
      unawaited(controller().startShift());
      await tester.pump();

      expect(backend.calls.single.name, 'setBarberStatus');
      expect(backend.calls.single.payload, containsPair('status', 'available'));
      expect(state(), const ConsoleState(pending: ConsoleAction.startShift));

      docs.emit(_queue, queueWith('available'));
      await tester.pump();
      expect(state(), const ConsoleState(settling: true));

      await tester.pump(ConsoleController.settleDelay);
      expect(state(), const ConsoleState());
    });

    testConsole('se a fila já chegou quando o servidor responde, não espera de novo', (
      tester,
    ) async {
      arrange();
      backend.gate = Completer<void>();
      unawaited(controller().startShift());
      await tester.pump();

      docs.emit(_queue, queueWith('available'));
      await tester.pump();
      // Ainda enviando: a fila sozinha não encerra o pedido.
      expect(state().pending, ConsoleAction.startShift);

      backend.gate!.complete();
      await tester.pump();
      expect(state(), const ConsoleState(settling: true));

      await tester.pump(ConsoleController.settleDelay);
      expect(state().busy, isFalse);
    });

    testConsole('sem confirmação da fila, desiste de esperar depois do limite', (tester) async {
      arrange(queue: queueWith('available'));
      unawaited(controller().pause());
      await tester.pump();
      expect(backend.calls.single.payload, containsPair('status', 'paused'));

      await tester.pump(ConsoleController.confirmationTimeout - const Duration(milliseconds: 1));
      expect(state().pending, ConsoleAction.pause);

      await tester.pump(const Duration(milliseconds: 1));
      expect(state(), const ConsoleState(settling: true));

      await tester.pump(ConsoleController.settleDelay);
      expect(state(), const ConsoleState());
    });

    testConsole('voltar da pausa e encerrar pedem os status certos', (tester) async {
      arrange(queue: queueWith('paused'));
      unawaited(controller().startShift(resuming: true));
      await tester.pump();
      expect(state().pending, ConsoleAction.resume);
      expect(backend.calls.last.payload, containsPair('status', 'available'));
      await letSettle(tester);

      unawaited(controller().endShift());
      await tester.pump();
      expect(state().pending, ConsoleAction.endShift);
      expect(backend.calls.last.payload, containsPair('status', 'off'));
      await letSettle(tester);
    });

    testConsole('pedido recusado deixa a falha no estado e libera na hora', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => throw FakeCallables.domainError('finish-current-first');

      unawaited(controller().endShift());
      await tester.pump();

      expect(
        state(),
        const ConsoleState(failure: QueueRuleFailure(QueueErrorCode.finishCurrentFirst)),
      );
      expect(state().busy, isFalse);
    });

    testConsole('uma nova tentativa limpa a falha anterior', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => throw FakeCallables.domainError('finish-current-first');
      unawaited(controller().endShift());
      await tester.pump();

      backend.handler = null;
      unawaited(controller().pause());
      await tester.pump();

      expect(state().failure, isNull);
      await letSettle(tester);
    });
  });

  group('"Próximo!", "Não veio" e desfazer', () {
    testConsole('"Próximo!" fica em aberto até a fila mostrar o chamado na cadeira', (
      tester,
    ) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => calledLucas();

      unawaited(controller().callNext());
      await tester.pump();

      expect(backend.calls.single.name, 'callNext');
      expect(backend.calls.single.payload, containsPair('outcome', 'done'));
      expect(state().pending, ConsoleAction.callNext);
      // O servidor já disse quem chamou: a tela pode avisar e oferecer o desfazer.
      expect(
        state().lastAdvance?.result.called,
        const CalledTicket(ticketId: 't2', number: 2, label: 'Lucas M.'),
      );

      docs.emit(_queue, queueWith('available', serving: lucasServed()));
      await tester.pump();
      expect(state().settling, isTrue);

      await tester.pump(ConsoleController.settleDelay);
      expect(state().busy, isFalse);
      expect(state().lastAdvance, isNotNull);
    });

    testConsole('"Não veio" manda o desfecho certo', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => {
        'finished': {'ticketId': 't2', 'outcome': 'no_show'},
        'called': null,
      };

      unawaited(controller().callNext(noShow: true));
      await tester.pump();

      expect(backend.calls.single.name, 'callNext');
      expect(backend.calls.single.payload, containsPair('outcome', 'no_show'));
      expect(state().pending, ConsoleAction.noShow);
      expect(state().lastAdvance?.result.finishedOutcome, FinishOutcome.noShow);
      await letSettle(tester);
    });

    testConsole('finalizar sem chamar fica em aberto até a cadeira esvaziar', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => {
        'finished': {'ticketId': 't2', 'outcome': 'done'},
        'called': null,
      };

      unawaited(controller().finishCurrent());
      await tester.pump();
      expect(backend.calls.single.name, 'finishCurrent');
      expect(state().pending, ConsoleAction.finish);

      docs.emit(_queue, queueWith('available'));
      await tester.pump();
      expect(state().settling, isTrue);
      await tester.pump(ConsoleController.settleDelay);
    });

    testConsole('fila vazia e ninguém na cadeira: nada a desfazer', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => {'finished': null, 'called': null};

      unawaited(controller().callNext());
      await tester.pump();

      expect(state().lastAdvance, isNull);
      // A fila já está como o pedido a deixaria: não há o que esperar.
      expect(state().settling, isTrue);
      await tester.pump(ConsoleController.settleDelay);
    });

    testConsole('cada avanço gera um aviso novo, mesmo com resultado igual', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => calledLucas();

      unawaited(controller().callNext());
      await tester.pump();
      final first = state().lastAdvance;
      await tester.pump(ConsoleController.settleDelay);

      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);

      expect(state().lastAdvance, isNot(first));
      expect(state().lastAdvance?.result, first?.result);
    });

    testConsole('desfazer limpa o aviso e espera a cadeira voltar ao que era', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => name == 'callNext' ? calledLucas() : null;
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);
      expect(state().lastAdvance, isNotNull);

      unawaited(controller().undoLast());
      await tester.pump();

      expect(backend.calls.last.name, 'undoLast');
      expect(state(), const ConsoleState(pending: ConsoleAction.undo));

      // Outra mudança na fila (alguém entrou) não é a confirmação: Lucas segue na cadeira.
      docs.emit(_queue, queueWith('available', serving: lucasServed(), version: 8));
      await tester.pump();
      expect(state().pending, ConsoleAction.undo);

      docs.emit(_queue, queueWith('available', version: 9));
      await tester.pump();
      expect(state().settling, isTrue);
      await tester.pump(ConsoleController.settleDelay);
    });

    testConsole('desfazer recusado mantém a falha à vista', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => throw FakeCallables.domainError('undo-expired');

      unawaited(controller().undoLast());
      await tester.pump();

      expect(state().failure, const QueueRuleFailure(QueueErrorCode.undoExpired));
      expect(state().busy, isFalse);
    });

    testConsole('sem confirmação da fila, o "Próximo!" libera depois do limite', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => calledLucas();

      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.confirmationTimeout - const Duration(milliseconds: 1));
      expect(state().pending, ConsoleAction.callNext);

      await tester.pump(const Duration(milliseconds: 1));
      expect(state().settling, isTrue);
      await tester.pump(ConsoleController.settleDelay);
      expect(state().busy, isFalse);
    });

    testConsole('o aviso vence quando acaba o prazo de desfazer', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => calledLucas();

      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.undoWindow - const Duration(milliseconds: 1));
      expect(state().lastAdvance, isNotNull);

      await tester.pump(const Duration(milliseconds: 1));
      expect(state(), const ConsoleState());
    });

    testConsole('desfazer não espera a fila confirmar o avanço', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => name == 'callNext' ? calledLucas() : null;
      unawaited(controller().callNext());
      await tester.pump();
      expect(state().pending, ConsoleAction.callNext);

      unawaited(controller().undoLast());
      await tester.pump();

      expect(backend.calls.last.name, 'undoLast');
      // A fila ainda está como antes do avanço, que é como o desfazer a deixa: nada a esperar.
      expect(state(), const ConsoleState(settling: true));

      await tester.pump(ConsoleController.settleDelay);
      // O limite de espera do avanço desfeito não mexe mais no estado.
      await tester.pump(ConsoleController.confirmationTimeout);
      expect(state(), const ConsoleState());
    });

    testConsole('desfazer não espera o descanso dos botões', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => name == 'callNext' ? calledLucas() : null;
      unawaited(controller().callNext());
      await tester.pump();
      docs.emit(_queue, queueWith('available', serving: lucasServed()));
      await tester.pump();
      expect(state().settling, isTrue);

      unawaited(controller().undoLast());
      await tester.pump();

      expect(backend.calls.last.name, 'undoLast');
      expect(state(), const ConsoleState(pending: ConsoleAction.undo));

      docs.emit(_queue, queueWith('available', version: 9));
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);
      expect(state(), const ConsoleState());
    });

    testConsole('com outro pedido a caminho, o desfazer não é enviado e o aviso volta', (
      tester,
    ) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => name == 'callNext' ? calledLucas() : null;
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);
      final offered = state().lastAdvance;

      backend.gate = Completer<void>();
      unawaited(controller().pause());
      await tester.pump();
      unawaited(controller().undoLast());
      await tester.pump();

      expect(backend.calls.map((call) => call.name), ['callNext', 'setBarberStatus']);
      expect(state().pending, ConsoleAction.pause);
      // Aviso novo com o mesmo conteúdo: a tela mostra de novo o que o toque escondeu.
      expect(state().lastAdvance, isNot(offered));
      expect(state().lastAdvance?.result, offered?.result);

      backend.gate!.complete();
      await tester.pump();
      await letSettle(tester);
    });

    testConsole('desfazer que não chegou ao servidor repõe o aviso para tentar de novo', (
      tester,
    ) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) =>
          name == 'callNext' ? calledLucas() : throw const CallableException('unavailable');
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);
      final offered = state().lastAdvance;

      unawaited(controller().undoLast());
      // Três tentativas com o mesmo pedido, com espera entre elas.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(backend.calls.where((call) => call.name == 'undoLast'), hasLength(3));
      expect(state().failure, isA<NetworkFailure>());
      expect(state().busy, isFalse);
      expect(state().lastAdvance, isNot(offered));
      expect(state().lastAdvance?.result, offered?.result);
    });

    testConsole('desfazer recusado pelo servidor retira o aviso', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) =>
          name == 'callNext' ? calledLucas() : throw FakeCallables.domainError('undo-conflict');
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);

      unawaited(controller().undoLast());
      await tester.pump();

      expect(
        state(),
        const ConsoleState(failure: QueueRuleFailure(QueueErrorCode.undoConflict)),
      );
    });

    testConsole('o avanço diz ao servidor quem a tela mostra na cadeira', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => {
        'finished': {'ticketId': 't2', 'outcome': 'done'},
        'called': null,
      };
      // A fila precisa ter chegado: na tela, a barra de ação só existe depois disso.
      await tester.pump();

      unawaited(controller().finishCurrent());
      await tester.pump();

      expect(backend.calls.single.payload, containsPair('expectedServingTicketId', 't2'));
      await letSettle(tester);
    });

    testConsole('com a cadeira vazia, o avanço diz que não vê ninguém nela', (tester) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => {'finished': null, 'called': null};
      // Com a fila já carregada: o nulo vem de "cadeira vazia", não de "ainda não sei".
      await tester.pump();

      unawaited(controller().callNext());
      await tester.pump();

      // Nulo, e não ausente: sem o campo o servidor não conferiria a cadeira.
      expect(backend.calls.single.payload, containsPair('expectedServingTicketId', null));
      await tester.pump(ConsoleController.settleDelay);
    });

    testConsole('se o servidor vê outra pessoa na cadeira, recusa e nada fica em oferta', (
      tester,
    ) async {
      arrange(queue: queueWith('available'));
      backend.handler = (name, payload) => throw FakeCallables.domainError('serving-changed');

      unawaited(controller().callNext());
      await tester.pump();

      expect(
        state(),
        const ConsoleState(failure: QueueRuleFailure(QueueErrorCode.servingChanged)),
      );
    });

    testConsole('depois de uma falha de rede, o novo toque repete o mesmo pedido', (tester) async {
      arrange(queue: queueWith('available'));
      await tester.pump();
      backend.handler = (name, payload) => throw const CallableException('unavailable');

      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(state().failure, isA<NetworkFailure>());
      final sent = backend.calls.last.payload;

      // O servidor tinha aplicado a primeira tentativa, e a tela já mostra Lucas na cadeira.
      docs.emit(_queue, queueWith('available', serving: lucasServed()));
      await tester.pump();
      backend.handler = (name, payload) => calledLucas();
      unawaited(controller().callNext());
      await tester.pump();

      // O mesmo pedido, com a cadeira de quando o barbeiro tocou: o servidor devolve o resultado
      // que já tinha, em vez de finalizar o Lucas e chamar outro.
      expect(backend.calls.last.payload['requestId'], sent['requestId']);
      expect(backend.calls.last.payload, containsPair('expectedServingTicketId', null));
      expect(state().lastAdvance?.result.called?.ticketId, 't2');
      await tester.pump(ConsoleController.settleDelay);

      // Respondido, o pedido está encerrado: o próximo toque é uma intenção nova.
      unawaited(controller().callNext());
      await tester.pump();
      expect(backend.calls.last.payload['requestId'], isNot(sent['requestId']));
      expect(backend.calls.last.payload, containsPair('expectedServingTicketId', 't2'));
      await tester.pump(ConsoleController.settleDelay);
    });

    testConsole('passado o prazo, o toque depois da falha de rede é um pedido novo', (
      tester,
    ) async {
      arrange(queue: queueWith('available'));
      await tester.pump();
      backend.handler = (name, payload) => throw const CallableException('unavailable');
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final sent = backend.calls.last.payload;

      // Muito depois, com outra pessoa na cadeira: o toque não é mais a repetição daquele pedido.
      await tester.pump(ConsoleController.unansweredLifetime);
      docs.emit(_queue, queueWith('available', serving: lucasServed()));
      await tester.pump();
      backend.handler = (name, payload) => {'finished': null, 'called': null};
      unawaited(controller().callNext());
      await tester.pump();

      expect(backend.calls.last.payload['requestId'], isNot(sent['requestId']));
      expect(backend.calls.last.payload, containsPair('expectedServingTicketId', 't2'));
      await letSettle(tester);
    });

    testConsole('com a tela atrasada, o novo toque manda quem ela ainda mostra na cadeira', (
      tester,
    ) async {
      arrange(queue: queueWith('available'));
      await tester.pump();
      backend.handler = (name, payload) => calledLucas();
      unawaited(controller().callNext());
      await tester.pump();
      // A fila não confirmou: passado o limite, os botões voltam com a tela ainda antiga.
      await letSettle(tester);
      expect(state().busy, isFalse);

      backend.handler = (name, payload) => throw FakeCallables.domainError('serving-changed');
      unawaited(controller().callNext());
      await tester.pump();

      // Manda o que a tela mostra (ninguém), e não quem a resposta anterior disse ter chamado:
      // é o servidor que decide se a tela está em dia.
      expect(backend.calls.last.payload, containsPair('expectedServingTicketId', null));
      expect(state().failure, const QueueRuleFailure(QueueErrorCode.servingChanged));

      docs.emit(_queue, queueWith('available', serving: lucasServed()));
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);
      backend.handler = (name, payload) => {'finished': null, 'called': null};
      unawaited(controller().callNext());
      await tester.pump();
      expect(backend.calls.last.payload, containsPair('expectedServingTicketId', 't2'));
      await letSettle(tester);
    });

    testConsole(
      'recusado porque a cadeira mudou: quando a tela mostra a mudança, os botões descansam',
      (
        tester,
      ) async {
        arrange(queue: queueWith('available'));
        await tester.pump();
        backend.handler = (name, payload) => throw FakeCallables.domainError('serving-changed');
        unawaited(controller().callNext());
        await tester.pump();
        expect(state().busy, isFalse);

        // Outra mudança na fila, com a cadeira igual, não é o que se espera.
        docs.emit(_queue, queueWith('available', version: 8));
        await tester.pump();
        expect(state().busy, isFalse);

        docs.emit(_queue, queueWith('available', serving: lucasServed(), version: 9));
        await tester.pump();
        // O botão passou a apontar para outra pessoa: inerte por um instante, com o motivo à vista.
        expect(
          state(),
          const ConsoleState(
            settling: true,
            failure: QueueRuleFailure(QueueErrorCode.servingChanged),
          ),
        );

        await tester.pump(ConsoleController.settleDelay);
        expect(
          state(),
          const ConsoleState(failure: QueueRuleFailure(QueueErrorCode.servingChanged)),
        );
      },
    );

    testConsole('resposta atrasada: o desfazer só fica pelo que resta da janela', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      await tester.pump();
      backend
        ..handler = ((name, payload) => calledLucas())
        ..gate = Completer<void>();
      unawaited(controller().callNext());
      await tester.pump(const Duration(seconds: 10));

      backend.gate!.complete();
      await tester.pump();

      // A janela conta do envio: 10 dos 15 segundos já passaram.
      expect(state().lastAdvance?.undoFor, const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5) - const Duration(milliseconds: 1));
      expect(state().lastAdvance, isNotNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(state().lastAdvance, isNull);
    });

    testConsole('resposta que chega depois da janela não oferece desfazer', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      await tester.pump();
      backend
        ..handler = ((name, payload) => calledLucas())
        ..gate = Completer<void>();
      unawaited(controller().callNext());
      await tester.pump(ConsoleController.undoWindow);

      backend.gate!.complete();
      await tester.pump();

      expect(state().lastAdvance, isNull);
      await tester.pump(ConsoleController.settleDelay);
    });

    testConsole('uma ação diferente depois da falha de rede é um pedido novo', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      await tester.pump();
      backend.handler = (name, payload) => throw const CallableException('unavailable');
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final sent = backend.calls.last.payload;

      backend.handler = (name, payload) => throw FakeCallables.domainError('serving-changed');
      unawaited(controller().callNext(noShow: true));
      await tester.pump();

      expect(backend.calls.last.payload['requestId'], isNot(sent['requestId']));
      expect(backend.calls.last.payload, containsPair('outcome', 'no_show'));
    });

    testConsole('o prazo do aviso é a janela de desfazer que o servidor informou', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => {...calledLucas(), 'undoWindowSec': 40};

      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(const Duration(seconds: 40) - const Duration(milliseconds: 1));
      expect(state().lastAdvance, isNotNull);

      await tester.pump(const Duration(milliseconds: 1));
      expect(state().lastAdvance, isNull);
    });

    testConsole('um avanço recusado mantém o desfazer do avanço anterior', (tester) async {
      arrange(queue: queueWith('available', serving: lucasServed()));
      backend.handler = (name, payload) => calledLucas();
      unawaited(controller().callNext());
      await tester.pump();
      await tester.pump(ConsoleController.settleDelay);
      final offered = state().lastAdvance;

      backend.handler = (name, payload) => throw FakeCallables.domainError('barber-not-available');
      unawaited(controller().callNext());
      await tester.pump();

      expect(state().failure, const QueueRuleFailure(QueueErrorCode.barberNotAvailable));
      expect(state().lastAdvance, offered);
    });
  });

  group('um comando por vez', () {
    testConsole('enquanto ocupado, outro pedido é ignorado, seja qual for', (tester) async {
      arrange(queue: queueWith('available'));
      backend.gate = Completer<void>();
      unawaited(controller().pause());
      await tester.pump();
      unawaited(controller().callNext());
      unawaited(controller().endShift());
      await tester.pump();

      expect(backend.calls, hasLength(1));
      expect(state().pending, ConsoleAction.pause);

      backend.gate!.complete();
      await tester.pump();
      await letSettle(tester);
    });

    testConsole('se o pedido estourar com um erro de programação, a tela não fica presa', (
      tester,
    ) async {
      arrange(queue: queueWith('available'));
      // Um Error (e não uma Exception) atravessa a camada de dados: é bug, não falha esperada.
      backend.handler = (name, payload) => throw StateError('bug');

      final request = expectLater(controller().pause(), throwsStateError);
      await tester.pump();
      await request;

      expect(state().busy, isFalse);
      expect(state().failure, isA<UnexpectedFailure>());
    });

    testConsole('descartado no meio do pedido, não mexe mais no estado nem deixa temporizador', (
      tester,
    ) async {
      arrange(queue: queueWith('available'));
      backend.gate = Completer<void>();
      unawaited(controller().pause());
      await tester.pump();

      container.dispose();
      backend.gate!.complete();
      await tester.pump();
      await tester.pump(ConsoleController.confirmationTimeout);

      expect(tester.takeException(), isNull);
    });
  });
}
