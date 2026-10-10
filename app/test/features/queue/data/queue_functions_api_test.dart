import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/queue/data/queue_functions_api.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

/// Backend falso: registra cada chamada e responde com a próxima resposta programada.
final class FakeBackend {
  FakeBackend(this._responses);

  final List<Object? Function()> _responses;
  final calls = <({String name, JsonMap payload})>[];

  Future<Object?> invoke(String name, JsonMap payload) async {
    calls.add((name: name, payload: payload));
    return _responses.removeAt(0)();
  }
}

Object? Function() respond(Object? data) => () => data;

Object? Function() failWith(String code, {Object? details}) =>
    () => throw CallableException(code, details: details);

void main() {
  late List<Duration> sleeps;
  var requestCounter = 0;

  QueueFunctionsApi apiWith(FakeBackend backend) => QueueFunctionsApi(
    invoke: backend.invoke,
    newRequestId: () => 'req-${++requestCounter}',
    sleep: (duration) async => sleeps.add(duration),
  );

  setUp(() {
    sleeps = [];
    requestCounter = 0;
  });

  group('joinQueue', () {
    test('envia o payload com requestId e devolve o ticket', () async {
      final backend = FakeBackend([
        respond({'ticketId': 'abc', 'number': 7}),
      ]);

      final result = await apiWith(backend).joinQueue(
        shopId: 'barbearia-do-ze',
        name: 'Lucas',
        serviceId: 'corte',
        source: TicketSource.qr,
      );

      expect(result, const Ok(JoinedTicket(ticketId: 'abc', number: 7)));
      expect(backend.calls.single.name, 'joinQueue');
      expect(backend.calls.single.payload, {
        'requestId': 'req-1',
        'shopId': 'barbearia-do-ze',
        'name': 'Lucas',
        'serviceId': 'corte',
        'source': 'qr',
      });
    });

    test('inclui o barbeiro preferido quando informado', () async {
      final backend = FakeBackend([
        respond({'ticketId': 'abc', 'number': 1}),
      ]);
      await apiWith(backend).joinQueue(
        shopId: 's',
        name: 'Lucas',
        serviceId: 'corte',
        source: TicketSource.link,
        preferredBarberId: 'joao',
      );
      expect(backend.calls.single.payload['preferredBarberId'], 'joao');
    });

    test('regra de negócio vira QueueRuleFailure, sem novas tentativas', () async {
      final backend = FakeBackend([
        failWith('failed-precondition', details: {'code': 'already-in-queue'}),
      ]);

      final result = await apiWith(
        backend,
      ).joinQueue(shopId: 's', name: 'Lucas', serviceId: 'corte', source: TicketSource.link);

      expect(result, const Err<JoinedTicket>(QueueRuleFailure(QueueErrorCode.alreadyInQueue)));
      expect(backend.calls, hasLength(1));
    });

    test('rate limit informa quando tentar de novo', () async {
      final backend = FakeBackend([
        failWith('resource-exhausted', details: {'code': 'rate-limited', 'retryAfterMs': 90000}),
      ]);

      final result = await apiWith(
        backend,
      ).joinQueue(shopId: 's', name: 'Lucas', serviceId: 'corte', source: TicketSource.link);

      expect(
        result.failureOrNull,
        const QueueRuleFailure(QueueErrorCode.rateLimited, retryAfter: Duration(seconds: 90)),
      );
    });
  });

  group('novas tentativas', () {
    test('repete falhas transitórias com o MESMO requestId e espera exponencial', () async {
      final backend = FakeBackend([
        failWith('unavailable'),
        failWith('deadline-exceeded'),
        respond({'finished': null, 'called': null}),
      ]);

      final result = await apiWith(backend).callNext(shopId: 's', outcome: FinishOutcome.done);

      expect(result, const Ok(AdvanceResult()));
      expect(backend.calls.map((c) => c.payload['requestId']).toSet(), {'req-1'});
      expect(sleeps, [const Duration(milliseconds: 400), const Duration(milliseconds: 800)]);
    });

    test('desiste após o limite e devolve NetworkFailure', () async {
      final backend = FakeBackend([failWith('unavailable'), failWith('unavailable'), failWith('unavailable')]);

      final result = await apiWith(backend).undoLast(shopId: 's');

      expect(result, const Err<void>(NetworkFailure()));
      expect(backend.calls, hasLength(3));
    });

    test('cada comando novo ganha um requestId novo', () async {
      final backend = FakeBackend([respond(null), respond(null)]);
      final api = apiWith(backend);

      await api.setAcceptingEntries(shopId: 's', accepting: false);
      await api.setAcceptingEntries(shopId: 's', accepting: true);

      expect(backend.calls.map((c) => c.payload['requestId']), ['req-1', 'req-2']);
    });
  });

  group('mapeamento de erros', () {
    final cases = <String, Failure>{
      'unauthenticated': const UnauthenticatedFailure(),
      'permission-denied': const PermissionFailure(),
      'not-found': const NotFoundFailure(),
    };
    for (final MapEntry(key: code, value: failure) in cases.entries) {
      test('$code → ${failure.runtimeType}', () async {
        final backend = FakeBackend([failWith(code)]);
        final result = await apiWith(backend).removeTicket(shopId: 's', ticketId: 't');
        expect(result.failureOrNull, failure);
      });
    }

    test('código de negócio desconhecido (app desatualizado) vira UnexpectedFailure', () async {
      final backend = FakeBackend([
        failWith('failed-precondition', details: {'code': 'codigo-do-futuro'}),
      ]);
      final result = await apiWith(backend).undoLast(shopId: 's');
      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });

    test('resposta fora do contrato vira UnexpectedFailure', () async {
      final backend = FakeBackend([
        respond({'ticketId': 123}),
      ]);
      final result = await apiWith(
        backend,
      ).joinQueue(shopId: 's', name: 'Lucas', serviceId: 'corte', source: TicketSource.link);
      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });
  });

  group('callNext', () {
    test('converte o resultado do "Próximo!"', () async {
      final backend = FakeBackend([
        respond({
          'finished': {'ticketId': 't1', 'outcome': 'no_show'},
          'called': {'ticketId': 't2', 'number': 2, 'label': 'Lucas M.'},
        }),
      ]);

      final result = await apiWith(backend).callNext(shopId: 's', outcome: FinishOutcome.noShow);

      expect(backend.calls.single.payload['outcome'], 'no_show');
      expect(
        result,
        const Ok(
          AdvanceResult(
            finishedTicketId: 't1',
            finishedOutcome: FinishOutcome.noShow,
            called: CalledTicket(ticketId: 't2', number: 2, label: 'Lucas M.'),
          ),
        ),
      );
    });
  });
}
