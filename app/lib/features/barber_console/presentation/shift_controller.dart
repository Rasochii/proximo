import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';
import 'package:proximo/features/queue/presentation/queue_providers.dart';

/// Barbeiro de uma barbearia: a chave do [shiftControllerProvider].
typedef ShiftKey = ({String shopId, String barberId});

@immutable
final class ShiftState {
  const ShiftState({this.requested, this.settling = false, this.failure});

  /// Status pedido que a fila pública ainda não confirmou; `null` quando não há pedido em aberto.
  final BarberStatus? requested;

  /// Breve espera depois de a tela mudar, para um segundo toque impaciente não cair no botão
  /// novo que apareceu no mesmo lugar.
  final bool settling;

  /// Falha do último pedido; some ao tentar de novo.
  final Failure? failure;

  /// Enquanto ocupado, a tela não aceita outro pedido.
  bool get busy => requested != null || settling;

  @override
  bool operator ==(Object other) =>
      other is ShiftState &&
      other.requested == requested &&
      other.settling == settling &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(requested, settling, failure);

  @override
  String toString() =>
      'ShiftState(requested: ${requested?.wire}, settling: $settling, failure: $failure)';
}

/// Expediente do barbeiro logado numa barbearia: iniciar, pausar e encerrar.
///
/// O controller só envia o pedido. O status que a tela mostra vem da fila pública, atualizada
/// pelo servidor; por isso o pedido só é dado por encerrado quando a fila mostra o status pedido
/// (ou depois de [ShiftController.confirmationTimeout], para a tela nunca ficar presa).
final shiftControllerProvider = NotifierProvider.autoDispose
    .family<ShiftController, ShiftState, ShiftKey>(ShiftController.new);

class ShiftController extends Notifier<ShiftState> {
  ShiftController(this.key);

  final ShiftKey key;

  /// Quanto esperar a fila pública confirmar um pedido aceito pelo servidor.
  static const confirmationTimeout = Duration(seconds: 5);

  /// Quanto os botões ficam inertes depois de a tela trocar de situação.
  static const settleDelay = Duration(milliseconds: 700);

  Timer? _timer;

  @override
  ShiftState build() {
    ref
      ..onDispose(() => _timer?.cancel())
      ..listen(publicQueueProvider(key.shopId), (_, next) => _onQueue(next.value));
    return const ShiftState();
  }

  Future<void> setStatus(BarberStatus status) async {
    if (state.busy) return;
    state = ShiftState(requested: status);
    final result = await ref
        .read(barberQueueRepositoryProvider)
        .setBarberStatus(shopId: key.shopId, status: status);
    if (!ref.mounted) return;

    final failure = result.failureOrNull;
    if (failure != null) {
      state = ShiftState(failure: failure);
      return;
    }
    // O servidor aceitou. A fila pode já ter chegado com o status novo; senão, espera por ela.
    if (_statusIn(ref.read(publicQueueProvider(key.shopId)).value) == status) {
      _settle();
    } else {
      _restartTimer(confirmationTimeout, _settle);
    }
  }

  void _onQueue(PublicQueue? queue) {
    final requested = state.requested;
    if (requested == null || _timer == null) return;
    if (_statusIn(queue) == requested) _settle();
  }

  void _settle() {
    state = const ShiftState(settling: true);
    _restartTimer(settleDelay, () => state = const ShiftState());
  }

  void _restartTimer(Duration duration, void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      if (ref.mounted) action();
    });
  }

  BarberStatus _statusIn(PublicQueue? queue) => queue?.statusOf(key.barberId) ?? BarberStatus.off;
}
