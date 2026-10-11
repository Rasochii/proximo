import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/queue/data/queue_mappers.dart';
import 'package:proximo/features/queue/domain/eta.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('QueueMappers.publicQueue', () {
    test('converte a projeção pública gravada pelo backend', () {
      final queue = QueueMappers.publicQueue(publicQueueJson());

      expect(queue.shopName, 'Barbearia do Zé');
      expect(queue.entry.open, isTrue);
      expect(queue.entry.eta, const EstimatedEta(Duration(minutes: 85)));
      expect(queue.barbers.single.status, BarberStatus.available);
      expect(queue.barbers.single.servingNumber, 1);
      expect(queue.nowServing.single.label, 'Ana S.');
      expect(queue.waiting.map((t) => t.position), [1, 2]);
      expect(queue.waitingTicket('t3')?.eta, const EstimatedEta(Duration(minutes: 55)));
      expect(queue.servingTicket('t1')?.barberId, 'ze');
      expect(queue.updatedAt, DateTime.fromMillisecondsSinceEpoch(1791661200000));
    });

    test('lê até quando a fila vale e sabe dizer se ainda é a de hoje', () {
      final midnight = DateTime(2026, 10, 11);
      final queue = QueueMappers.publicQueue(publicQueueJson(validUntil: midnight));

      expect(queue.validUntil, midnight);
      expect(queue.isValidAt(DateTime(2026, 10, 10, 23, 59)), isTrue);
      expect(queue.isValidAt(midnight), isFalse);
      expect(queue.isValidAt(DateTime(2026, 10, 11, 8)), isFalse);
    });

    test('projeção antiga, sem prazo, continua valendo', () {
      final queue = QueueMappers.publicQueue(publicQueueJson());

      expect(queue.validUntil, isNull);
      expect(queue.isValidAt(DateTime(2030)), isTrue);
    });

    test('entrada fechada traz o motivo', () {
      final json = publicQueueJson()
        ..['entry'] = {
          'open': false,
          'reason': 'closing-soon',
          'eta': {'kind': 'beyond_closing'},
        };
      final queue = QueueMappers.publicQueue(json);

      expect(queue.entry.open, isFalse);
      expect(queue.entry.closedReason, QueueErrorCode.closingSoon);
      expect(queue.entry.eta, isA<BeyondClosingEta>());
    });

    test('aceita mapas no formato devolvido pelos SDKs nativos', () {
      final native = <Object?, Object?>{...publicQueueJson()};
      final queue = QueueMappers.publicQueue(asJsonMap(native));
      expect(queue.waitingCount, 2);
    });

    test('rejeita documento fora do contrato', () {
      expect(() => QueueMappers.publicQueue({'shopId': 1}), throwsFormatException);
    });
  });

  group('Eta', () {
    test('tipos desconhecidos viram UnknownEta (compatibilidade futura)', () {
      expect(QueueMappers.eta({'kind': 'novo-tipo'}), isA<UnknownEta>());
    });

    test('a faixa exibida tem amplitude proporcional e limitada', () {
      expect(const EstimatedEta(Duration.zero).rangeInMinutes, (min: 0, max: 0));
      expect(const EstimatedEta(Duration(minutes: 5)).rangeInMinutes, (min: 3, max: 7));
      expect(const EstimatedEta(Duration(minutes: 50)).rangeInMinutes, (min: 40, max: 60));
      expect(const EstimatedEta(Duration(minutes: 300)).rangeInMinutes, (min: 270, max: 330));
    });
  });

  test('QueueErrorCode cobre os códigos do backend e ignora desconhecidos', () {
    expect(QueueErrorCode.fromWire('already-in-queue'), QueueErrorCode.alreadyInQueue);
    expect(QueueErrorCode.fromWire('nao-existe'), isNull);
    expect(QueueErrorCode.fromWire(null), isNull);
  });
}
