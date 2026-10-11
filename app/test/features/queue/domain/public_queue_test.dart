import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/queue/data/queue_mappers.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';

import '../../../helpers/fixtures.dart';

/// Fila com [preferences] na ordem da espera: o barbeiro que cada cliente pediu (`null` = tanto faz).
PublicQueue queueWaitingFor(List<String?> preferences) {
  final json = publicQueueJson(waiting: preferences.length);
  final waiting = json['waiting']! as List<JsonMap>;
  for (final (index, preferred) in preferences.indexed) {
    waiting[index]['preferredBarberId'] = preferred;
  }
  return QueueMappers.publicQueue(json);
}

void main() {
  // A mesma regra do servidor (`advance`, em functions/src/domain/commands.ts): o console usa
  // este resultado para dizer quem será chamado e para escolher entre chamar e só finalizar.
  group('PublicQueue.nextFor', () {
    test('sem preferências, é o primeiro da espera', () {
      expect(queueWaitingFor([null, null]).nextFor('ze')?.number, 2);
    });

    test('pula quem pediu outro barbeiro', () {
      expect(queueWaitingFor(['joao', null]).nextFor('ze')?.number, 3);
    });

    test('quem pediu este barbeiro é chamado na sua vez', () {
      expect(queueWaitingFor(['joao', 'ze', null]).nextFor('ze')?.number, 3);
    });

    test('se todos esperam por outro barbeiro, não há quem chamar', () {
      expect(queueWaitingFor(['joao']).nextFor('ze'), isNull);
    });

    test('com a espera vazia, não há quem chamar', () {
      expect(queueWaitingFor([]).nextFor('ze'), isNull);
    });
  });
}
