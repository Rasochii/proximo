import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/barber_console/presentation/console_controller.dart';

import 'fake_auth.dart';
import 'fake_callables.dart';
import 'fixtures.dart';

const _shop = 'shops/barbearia-do-ze';
const _staff = 'staff/barbeiro-ze';

/// O documento da fila pública da barbearia dos testes do console.
const consoleQueue = 'publicQueues/barbearia-do-ze';

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

/// Os documentos que o console do Zé lê.
FakeDocuments consoleDocuments({JsonMap? queue}) => FakeDocuments({
  _shop: shopJson(),
  _staff: {'shopId': 'barbearia-do-ze', 'role': 'owner'},
  consoleQueue: ?queue,
});

/// Abre o app no console, com o Zé logado como dono da barbearia.
Future<({FakeDocuments docs, FakeCallables backend})> openConsole(
  WidgetTester tester, {
  JsonMap? queue,
  FakeCallables? backend,
  DateTime Function()? clock,
}) async {
  final docs = consoleDocuments(queue: queue);
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
