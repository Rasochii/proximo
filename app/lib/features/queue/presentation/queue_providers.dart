import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/config/clock.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/features/auth/presentation/auth_providers.dart';
import 'package:proximo/features/queue/data/queue_functions_api.dart';
import 'package:proximo/features/queue/data/queue_repositories_impl.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_repositories.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';

final queueFunctionsApiProvider = Provider<QueueFunctionsApi>(
  (ref) => QueueFunctionsApi(
    invoke: ref.watch(callableInvokerProvider),
    newRequestId: ref.watch(requestIdGeneratorProvider),
  ),
);

final customerQueueRepositoryProvider = Provider<CustomerQueueRepository>(
  (ref) => CustomerQueueRepositoryImpl(
    watch: ref.watch(documentWatcherProvider),
    api: ref.watch(queueFunctionsApiProvider),
  ),
);

final barberQueueRepositoryProvider = Provider<BarberQueueRepository>(
  (ref) => BarberQueueRepositoryImpl(ref.watch(queueFunctionsApiProvider)),
);

/// Fila pública de uma barbearia em tempo real. `null` = a fila de hoje ainda não foi aberta.
///
/// O servidor só regrava a fila quando alguém age, então depois da meia-noite o documento ainda
/// traz a fila de ontem. Quem diz até quando ela vale é o próprio servidor (`validUntil`); passado
/// o prazo, o app a trata como "ainda não aberta", inclusive se o dia virar com a tela aberta.
final publicQueueProvider = StreamProvider.autoDispose.family<PublicQueue?, String>((ref, shopId) {
  final now = ref.watch(clockProvider);
  Timer? expiry;
  ref.onDispose(() => expiry?.cancel());

  // Confere o prazo de minuto em minuto, em vez de um único temporizador até a meia-noite: o
  // temporizador não conta o tempo em que o aparelho ficou suspenso, e um tablet deixado ligado
  // de um dia para o outro voltaria mostrando a fila de ontem.
  void watchExpiry(DateTime validUntil) {
    final remaining = validUntil.difference(now());
    if (remaining <= Duration.zero) {
      // Venceu com a tela aberta: refaz a leitura, e a fila vencida passa a ser "não aberta".
      ref.invalidateSelf();
      return;
    }
    final wait = remaining < _expiryCheckInterval ? remaining : _expiryCheckInterval;
    expiry = Timer(wait, () => watchExpiry(validUntil));
  }

  return ref.watch(customerQueueRepositoryProvider).watchPublicQueue(shopId).map((queue) {
    expiry?.cancel();
    if (queue == null) return null;
    if (!queue.isValidAt(now())) return null;

    final validUntil = queue.validUntil;
    if (validUntil != null) watchExpiry(validUntil);
    return queue;
  });
});

/// De quanto em quanto tempo a tela confere se a fila pública venceu.
const _expiryCheckInterval = Duration(minutes: 1);

/// Ticket ativo do usuário logado; `null` sem login ou fora de fila.
final activeTicketProvider = StreamProvider.autoDispose<ActiveTicket?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(customerQueueRepositoryProvider).watchActiveTicket(user.uid);
});
