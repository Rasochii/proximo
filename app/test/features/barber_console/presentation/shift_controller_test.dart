import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/config/provider_retry.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/features/barber_console/presentation/shift_controller.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

import '../../../helpers/fake_callables.dart';
import '../../../helpers/fixtures.dart';

const _queue = 'publicQueues/barbearia-do-ze';
const ShiftKey _key = (shopId: 'barbearia-do-ze', barberId: 'barbeiro-ze');

/// Fila pública com o barbeiro do teste na situação pedida.
Map<String, Object?> queueWith(String status) => publicQueueJson(
  barbers: [
    {'id': 'barbeiro-ze', 'displayName': 'Zé', 'status': status, 'servingNumber': null},
  ],
);

// `testWidgets` dá um relógio falso: o tempo só anda com `tester.pump`, e os temporizadores do
// controller podem ser testados sem esperar de verdade.
void main() {
  late FakeDocuments docs;
  late FakeCallables backend;
  late ProviderContainer container;

  // Chamado dentro de cada teste, e não num setUp: o que é criado fora do corpo do teste fica
  // fora do relógio falso, e os temporizadores disparados pela fila rodariam em tempo real.
  void arrange() {
    docs = FakeDocuments();
    backend = FakeCallables();
    addTearDown(docs.dispose);
    container = ProviderContainer.test(
      retry: noAutomaticRetry,
      overrides: [
        documentWatcherProvider.overrideWithValue(docs.watch),
        callableInvokerProvider.overrideWithValue(backend.invoke),
      ],
    )..listen(shiftControllerProvider(_key), (_, _) {});
  }

  ShiftState state() => container.read(shiftControllerProvider(_key));
  ShiftController controller() => container.read(shiftControllerProvider(_key).notifier);

  testWidgets('pedido aceito fica em aberto até a fila mostrar o status pedido', (tester) async {
    arrange();
    unawaited(controller().setStatus(BarberStatus.available));
    await tester.pump();

    expect(state(), const ShiftState(requested: BarberStatus.available));

    docs.emit(_queue, queueWith('available'));
    await tester.pump();
    expect(state(), const ShiftState(settling: true));

    await tester.pump(ShiftController.settleDelay);
    expect(state(), const ShiftState());
  });

  testWidgets('se a fila já chegou quando o servidor responde, não espera de novo', (
    tester,
  ) async {
    arrange();
    backend.gate = Completer<void>();
    unawaited(controller().setStatus(BarberStatus.available));
    await tester.pump();

    docs.emit(_queue, queueWith('available'));
    await tester.pump();
    // Ainda enviando: a fila sozinha não encerra o pedido.
    expect(state().requested, BarberStatus.available);

    backend.gate!.complete();
    await tester.pump();
    expect(state(), const ShiftState(settling: true));

    await tester.pump(ShiftController.settleDelay);
    expect(state().busy, isFalse);
  });

  testWidgets('sem confirmação da fila, desiste de esperar depois do limite', (tester) async {
    arrange();
    unawaited(controller().setStatus(BarberStatus.paused));
    await tester.pump();

    await tester.pump(ShiftController.confirmationTimeout - const Duration(milliseconds: 1));
    expect(state().requested, BarberStatus.paused);

    await tester.pump(const Duration(milliseconds: 1));
    expect(state(), const ShiftState(settling: true));

    await tester.pump(ShiftController.settleDelay);
    expect(state(), const ShiftState());
  });

  testWidgets('pedido recusado deixa a falha no estado e libera na hora', (tester) async {
    arrange();
    backend.handler = (name, payload) => throw FakeCallables.domainError('finish-current-first');

    unawaited(controller().setStatus(BarberStatus.off));
    await tester.pump();

    expect(
      state(),
      const ShiftState(failure: QueueRuleFailure(QueueErrorCode.finishCurrentFirst)),
    );
    expect(state().busy, isFalse);
  });

  testWidgets('uma nova tentativa limpa a falha anterior', (tester) async {
    arrange();
    backend.handler = (name, payload) => throw FakeCallables.domainError('finish-current-first');
    unawaited(controller().setStatus(BarberStatus.off));
    await tester.pump();

    backend.handler = null;
    unawaited(controller().setStatus(BarberStatus.paused));
    await tester.pump();

    expect(state().failure, isNull);
    await tester.pump(ShiftController.confirmationTimeout);
    await tester.pump(ShiftController.settleDelay);
  });

  testWidgets('enquanto ocupado, outro pedido é ignorado', (tester) async {
    arrange();
    backend.gate = Completer<void>();
    unawaited(controller().setStatus(BarberStatus.paused));
    await tester.pump();
    unawaited(controller().setStatus(BarberStatus.off));
    await tester.pump();

    expect(backend.calls, hasLength(1));
    expect(state().requested, BarberStatus.paused);

    backend.gate!.complete();
    await tester.pump();
    await tester.pump(ShiftController.confirmationTimeout);
    await tester.pump(ShiftController.settleDelay);
  });

  testWidgets('se o pedido estourar com um erro de programação, a tela não fica presa', (
    tester,
  ) async {
    arrange();
    // Um Error (e não uma Exception) atravessa a camada de dados: é bug, não falha esperada.
    backend.handler = (name, payload) => throw StateError('bug');

    final request = expectLater(controller().setStatus(BarberStatus.paused), throwsStateError);
    await tester.pump();
    await request;

    expect(state().busy, isFalse);
    expect(state().failure, isA<UnexpectedFailure>());
  });

  testWidgets('descartado no meio do pedido, não mexe mais no estado nem deixa temporizador', (
    tester,
  ) async {
    arrange();
    backend.gate = Completer<void>();
    unawaited(controller().setStatus(BarberStatus.paused));
    await tester.pump();

    container.dispose();
    backend.gate!.complete();
    await tester.pump();
    await tester.pump(ShiftController.confirmationTimeout);

    expect(tester.takeException(), isNull);
  });
}
