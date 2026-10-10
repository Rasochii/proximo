import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/app.dart';
import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/core/json/json.dart';

/// Documento `shops/barbearia-do-ze` no formato gravado pelo backend.
JsonMap shopJson() => {
  'name': 'Barbearia do Zé',
  'slug': 'barbearia-do-ze',
  'timezone': 'America/Sao_Paulo',
  'schedule': {
    'sun': <Object?>[],
    'mon': [
      {'start': '09:00', 'end': '12:00'},
      {'start': '13:00', 'end': '19:00'},
    ],
  },
  'services': [
    {'id': 'corte', 'name': 'Corte', 'defaultDurationMin': 30, 'active': true},
    {'id': 'pigmentacao', 'name': 'Pigmentação', 'defaultDurationMin': 60, 'active': false},
  ],
  'settings': {'closeEntryMinutesBefore': 15},
};

/// Documento `publicQueues/barbearia-do-ze` exatamente como `buildPublicQueue` produz.
JsonMap publicQueueJson({int waiting = 2}) => {
  'shopId': 'barbearia-do-ze',
  'shopName': 'Barbearia do Zé',
  'slug': 'barbearia-do-ze',
  'dateKey': '2026-10-10',
  'entry': {
    'open': true,
    'reason': null,
    'eta': {'kind': 'estimated', 'startsInMin': 25 + waiting * 30},
  },
  'barbers': [
    {'id': 'ze', 'displayName': 'Zé', 'status': 'available', 'servingNumber': 1},
  ],
  'nowServing': [
    {'ticketId': 't1', 'number': 1, 'label': 'Ana S.', 'barberId': 'ze'},
  ],
  'waiting': [
    for (var i = 0; i < waiting; i++)
      {
        'ticketId': 't${i + 2}',
        'number': i + 2,
        'label': i.isEven ? 'Lucas M.' : 'João',
        'serviceId': 'corte',
        'preferredBarberId': null,
        'position': i + 1,
        'eta': {'kind': 'estimated', 'startsInMin': 25 + i * 30},
      },
  ],
  'waitingCount': waiting,
  'version': 7,
  'updatedAt': 1791661200000,
};

/// [DocumentWatcher] em memória: cada caminho guarda o último valor (como o Firestore, que sempre
/// entrega o estado atual a quem começa a observar) e o teste pode emitir atualizações ao vivo.
final class FakeDocuments {
  FakeDocuments([Map<String, JsonMap?> initial = const {}]) : _last = {...initial};

  final Map<String, JsonMap?> _last;
  final _controllers = <String, StreamController<JsonMap?>>{};

  StreamController<JsonMap?> _controller(String path) =>
      _controllers.putIfAbsent(path, StreamController<JsonMap?>.broadcast);

  /// Documentos não configurados se comportam como inexistentes (`null`).
  Stream<JsonMap?> watch(String path) async* {
    yield _last[path];
    yield* _controller(path).stream;
  }

  void emit(String path, JsonMap? data) {
    _last[path] = data;
    _controller(path).add(data);
  }

  void fail(String path, Object error) => _controller(path).addError(error);

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}

/// Monta o app inteiro com o backend falso (nenhum acesso ao Firebase).
///
/// Sem [invoke], qualquer chamada a uma callable falha o teste: o repositório da fila depende do
/// invocador mesmo nas telas que só leem, e o provider real exigiria o Firebase inicializado.
Future<void> pumpProximoApp(
  WidgetTester tester, {
  required DocumentWatcher watch,
  CallableInvoker? invoke,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // Sem novas tentativas automáticas: erros devem aparecer de imediato e sem timers pendentes.
      retry: (retryCount, error) => null,
      overrides: [
        documentWatcherProvider.overrideWithValue(watch),
        callableInvokerProvider.overrideWithValue(
          invoke ?? (name, payload) => fail('Callable "$name" chamada sem um invocador falso.'),
        ),
      ],
      child: const ProximoApp(),
    ),
  );
  await tester.pumpAndSettle();
}
