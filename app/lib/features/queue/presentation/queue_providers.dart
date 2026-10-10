import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Fila pública de uma barbearia em tempo real. `null` = a fila ainda não foi aberta nenhuma vez.
final publicQueueProvider = StreamProvider.autoDispose.family<PublicQueue?, String>(
  (ref, shopId) => ref.watch(customerQueueRepositoryProvider).watchPublicQueue(shopId),
);

/// Ticket ativo do usuário logado; `null` sem login ou fora de fila.
final activeTicketProvider = StreamProvider.autoDispose<ActiveTicket?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(customerQueueRepositoryProvider).watchActiveTicket(user.uid);
});
