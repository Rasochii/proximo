import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/result/result.dart';
import 'package:proximo/features/queue/domain/public_queue.dart';
import 'package:proximo/features/queue/domain/queue_repositories.dart';
import 'package:proximo/features/queue/domain/queue_types.dart';
import 'package:proximo/features/queue/presentation/queue_providers.dart';

/// Barbeiro de uma barbearia: a chave do [consoleControllerProvider].
typedef ConsoleKey = ({String shopId, String barberId});

/// O que o barbeiro pode pedir no console.
enum ConsoleAction {
  startShift,
  pause,
  resume,
  endShift,

  /// "Próximo!": finaliza o atual como atendido e chama o seguinte.
  callNext,

  /// Finaliza o atual como atendido, sem chamar ninguém.
  finish,

  /// O cliente chamado não apareceu.
  noShow,
  undo,
}

/// Um "Próximo!", "Finalizar" ou "Não veio" que o servidor aceitou e que ainda pode ser desfeito.
/// O [id] distingue um aviso do seguinte, mesmo quando o resultado é igual.
@immutable
final class AdvanceNotice {
  const AdvanceNotice({required this.id, required this.result});

  final int id;
  final AdvanceResult result;

  @override
  bool operator ==(Object other) =>
      other is AdvanceNotice && other.id == id && other.result == result;

  @override
  int get hashCode => Object.hash(id, result);
}

@immutable
final class ConsoleState {
  const ConsoleState({this.pending, this.settling = false, this.failure, this.lastAdvance});

  /// Pedido que a fila pública ainda não confirmou; `null` quando não há pedido em aberto.
  final ConsoleAction? pending;

  /// Breve espera depois de a tela mudar, para um segundo toque impaciente não cair no botão
  /// novo que apareceu no mesmo lugar.
  final bool settling;

  /// Falha do último pedido; some ao tentar de novo.
  final Failure? failure;

  /// O último avanço da fila aceito, enquanto ainda dá para desfazer: a tela mostra o aviso com
  /// "Desfazer" quando ele aparece e tira quando ele some (desfeito, recusado ou vencido).
  final AdvanceNotice? lastAdvance;

  /// Enquanto ocupado, o console não aceita outro pedido: um comando por vez.
  bool get busy => pending != null || settling;

  @override
  bool operator ==(Object other) =>
      other is ConsoleState &&
      other.pending == pending &&
      other.settling == settling &&
      other.failure == failure &&
      other.lastAdvance == lastAdvance;

  @override
  int get hashCode => Object.hash(pending, settling, failure, lastAdvance);

  @override
  String toString() =>
      'ConsoleState(pending: ${pending?.name}, settling: $settling, failure: $failure, '
      'lastAdvance: ${lastAdvance?.id})';
}

/// Comandos do barbeiro logado numa barbearia: expediente, "Próximo!", "Não veio" e desfazer.
///
/// O controller só envia o pedido. O que a tela mostra vem da fila pública, atualizada pelo
/// servidor; por isso um pedido só é dado por encerrado quando a fila reflete o efeito dele (ou
/// depois de [ConsoleController.confirmationTimeout], para a tela nunca ficar presa). Enquanto
/// isso todos os botões ficam inertes: o segundo toque de quem tem pressa não vira outro comando.
/// A exceção é o Desfazer, que é a proteção contra o toque errado e não pode ser descartado.
final consoleControllerProvider = NotifierProvider.autoDispose
    .family<ConsoleController, ConsoleState, ConsoleKey>(ConsoleController.new);

class ConsoleController extends Notifier<ConsoleState> {
  ConsoleController(this.key);

  final ConsoleKey key;

  /// Quanto esperar a fila pública confirmar um pedido aceito pelo servidor.
  static const confirmationTimeout = Duration(seconds: 5);

  /// Quanto os botões ficam inertes depois de a tela trocar de situação.
  static const settleDelay = Duration(milliseconds: 700);

  /// Por quanto tempo o Desfazer fica em oferta depois de um avanço. É o padrão do servidor
  /// (`undoWindowSec`), que ainda tolera alguns segundos a mais pela demora da rede. A barbearia
  /// pode ter outro valor configurado; o app ainda não lê essa configuração.
  static const undoWindow = Duration(seconds: 15);

  Timer? _timer;
  Timer? _undoExpiry;

  /// Há um pedido a caminho do servidor, ainda sem resposta.
  bool _sending = false;

  /// Diz se a fila já mostra o efeito do pedido aceito; `null` enquanto o pedido está sendo
  /// enviado ou quando não há pedido em aberto.
  bool Function(PublicQueue? queue)? _confirmed;
  int _notices = 0;

  @override
  ConsoleState build() {
    ref
      ..onDispose(() {
        _timer?.cancel();
        _undoExpiry?.cancel();
      })
      ..listen(publicQueueProvider(key.shopId), (_, next) => _onQueue(next.value));
    return const ConsoleState();
  }

  /// Inicia o expediente ou volta da pausa.
  Future<void> startShift({bool resuming = false}) => _setStatus(
    resuming ? ConsoleAction.resume : ConsoleAction.startShift,
    BarberStatus.available,
  );

  Future<void> pause() => _setStatus(ConsoleAction.pause, BarberStatus.paused);

  Future<void> endShift() => _setStatus(ConsoleAction.endShift, BarberStatus.off);

  /// "Próximo!" ([noShow] falso) ou "Não veio": finaliza o atendimento atual e chama o seguinte.
  Future<void> callNext({bool noShow = false}) => _run<AdvanceResult>(
    noShow ? ConsoleAction.noShow : ConsoleAction.callNext,
    () => _repository.callNext(
      shopId: key.shopId,
      outcome: noShow ? FinishOutcome.noShow : FinishOutcome.done,
    ),
    confirmed: (queue, result) =>
        queue?.servedBy(key.barberId)?.ticketId == result.called?.ticketId,
    onAccepted: _rememberAdvance,
  );

  /// Finaliza o atendimento atual sem chamar ninguém (fila vazia, ou antes de uma pausa).
  Future<void> finishCurrent({bool noShow = false}) => _run<AdvanceResult>(
    noShow ? ConsoleAction.noShow : ConsoleAction.finish,
    () => _repository.finishCurrent(
      shopId: key.shopId,
      outcome: noShow ? FinishOutcome.noShow : FinishOutcome.done,
    ),
    confirmed: (queue, _) => queue?.servedBy(key.barberId) == null,
    onAccepted: _rememberAdvance,
  );

  /// Desfaz o último "Próximo!", "Finalizar" ou "Não veio" deste barbeiro.
  ///
  /// Não espera a fila confirmar o avanço nem o descanso dos botões: quem percebe o engano na
  /// hora toca em "Desfazer" justamente nesse intervalo.
  Future<void> undoLast() {
    final advance = state.lastAdvance;
    if (_sending) {
      // Outro pedido ainda está a caminho. O toque já tirou o aviso da tela; ele volta, para o
      // barbeiro tentar de novo em vez de achar que desfez.
      if (advance != null) _offerUndo(advance.result);
      return Future<void>.value();
    }
    _timer?.cancel();
    _timer = null;
    _confirmed = null;
    state = ConsoleState(lastAdvance: advance);

    return _run<void>(
      ConsoleAction.undo,
      () => _repository.undoLast(shopId: key.shopId),
      // Desfeito, a cadeira volta a quem estava nela antes do avanço (ou a ficar vazia).
      confirmed: (queue, _) =>
          advance == null ||
          queue?.servedBy(key.barberId)?.ticketId == advance.result.finishedTicketId,
      onAccepted: (_) => _withdrawUndo(),
    );
  }

  BarberQueueRepository get _repository => ref.read(barberQueueRepositoryProvider);

  PublicQueue? get _queue => ref.read(publicQueueProvider(key.shopId)).value;

  Future<void> _setStatus(ConsoleAction action, BarberStatus status) => _run<void>(
    action,
    () => _repository.setBarberStatus(shopId: key.shopId, status: status),
    // A fila pública só lista quem está em expediente: fora dela é "fora do expediente".
    confirmed: (queue, _) => (queue?.statusOf(key.barberId) ?? BarberStatus.off) == status,
  );

  void _rememberAdvance(AdvanceResult result) {
    // Fila vazia e ninguém na cadeira: o servidor não fez nada, então não há o que desfazer.
    if (result.called == null && result.finishedTicketId == null) return;
    _offerUndo(result);
    _undoExpiry?.cancel();
    _undoExpiry = Timer(undoWindow, () {
      _undoExpiry = null;
      if (ref.mounted) _setAdvance(null);
    });
  }

  /// Põe (ou repõe) o aviso com "Desfazer" na tela. O prazo continua sendo o do avanço original.
  void _offerUndo(AdvanceResult result) =>
      _setAdvance(AdvanceNotice(id: ++_notices, result: result));

  void _withdrawUndo() {
    _undoExpiry?.cancel();
    _undoExpiry = null;
    _setAdvance(null);
  }

  void _setAdvance(AdvanceNotice? advance) => state = ConsoleState(
    pending: state.pending,
    settling: state.settling,
    failure: state.failure,
    lastAdvance: advance,
  );

  void _fail(ConsoleAction action, Failure failure) {
    final advance = state.lastAdvance;
    state = ConsoleState(failure: failure, lastAdvance: advance);
    if (action != ConsoleAction.undo || advance == null) return;

    // O toque em "Desfazer" já tirou o aviso da tela. Se o servidor recusou, não há mais o que
    // oferecer; se o pedido nem chegou a ser atendido (rede, por exemplo), o aviso volta para o
    // barbeiro tentar de novo enquanto houver prazo.
    if (failure is QueueRuleFailure) {
      _withdrawUndo();
    } else {
      _offerUndo(advance.result);
    }
  }

  Future<void> _run<T>(
    ConsoleAction action,
    Future<Result<T>> Function() send, {
    required bool Function(PublicQueue? queue, T result) confirmed,
    void Function(T result)? onAccepted,
  }) async {
    if (state.busy) return;
    state = ConsoleState(pending: action, lastAdvance: state.lastAdvance);
    Result<T>? result;
    _sending = true;
    try {
      result = await send();
    } finally {
      _sending = false;
      // O repositório devolve as falhas esperadas como Result. Se ainda assim algo estourar (um
      // erro de programação, por exemplo), o erro segue para os logs, mas a tela não fica presa.
      if (result == null && ref.mounted) _fail(action, const UnexpectedFailure());
    }
    if (!ref.mounted) return;

    switch (result) {
      case Err<T>(:final failure):
        _fail(action, failure);
      case Ok<T>(:final value):
        onAccepted?.call(value);
        // O servidor aceitou. A fila pode já ter chegado com o efeito; senão, espera por ela.
        if (confirmed(_queue, value)) {
          _settle();
        } else {
          _confirmed = (queue) => confirmed(queue, value);
          _restartTimer(confirmationTimeout, _settle);
        }
    }
  }

  void _onQueue(PublicQueue? queue) {
    if (_confirmed?.call(queue) ?? false) _settle();
  }

  void _settle() {
    _confirmed = null;
    state = ConsoleState(settling: true, lastAdvance: state.lastAdvance);
    _restartTimer(
      settleDelay,
      () => state = ConsoleState(lastAdvance: state.lastAdvance),
    );
  }

  void _restartTimer(Duration duration, void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      if (ref.mounted) action();
    });
  }
}
