import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:proximo/core/config/clock.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
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

  /// Tira da fila alguém que ainda espera.
  removeTicket,
  closeEntries,
  openEntries,
}

/// Um "Próximo!", "Finalizar" ou "Não veio" que o servidor aceitou e que ainda pode ser desfeito.
/// O [id] distingue um aviso do seguinte, mesmo quando o resultado é igual.
@immutable
final class AdvanceNotice {
  const AdvanceNotice({required this.id, required this.result, required this.undoFor});

  final int id;
  final AdvanceResult result;

  /// Quanto restava da janela de desfazer quando o aviso foi oferecido pela primeira vez.
  final Duration undoFor;

  @override
  bool operator ==(Object other) =>
      other is AdvanceNotice &&
      other.id == id &&
      other.result == result &&
      other.undoFor == undoFor;

  @override
  int get hashCode => Object.hash(id, result, undoFor);
}

@immutable
final class ConsoleState {
  const ConsoleState({
    this.pending,
    this.settling = false,
    this.failure,
    this.failedAction,
    this.lastAdvance,
  });

  /// Pedido que a fila pública ainda não confirmou; `null` quando não há pedido em aberto.
  final ConsoleAction? pending;

  /// Breve espera depois de a tela mudar, para um segundo toque impaciente não cair no botão
  /// novo que apareceu no mesmo lugar.
  final bool settling;

  /// Falha do último pedido; some ao tentar de novo ou ao ser dispensada.
  final Failure? failure;

  /// O pedido que gerou [failure]: a tela mostra o motivo perto de onde o barbeiro tocou.
  final ConsoleAction? failedAction;

  /// O último avanço da fila aceito, enquanto ainda dá para desfazer: a tela mostra o aviso com
  /// "Desfazer" quando ele aparece e tira quando ele some (desfeito, recusado ou vencido).
  final AdvanceNotice? lastAdvance;

  /// Enquanto ocupado, o console não aceita outro pedido: um comando por vez.
  bool get busy => pending != null || settling;

  /// Este estado sem pedido em aberto, mantendo a falha e o aviso de desfazer.
  ConsoleState settled({bool settling = false}) => ConsoleState(
    settling: settling,
    failure: failure,
    failedAction: failedAction,
    lastAdvance: lastAdvance,
  );

  @override
  bool operator ==(Object other) =>
      other is ConsoleState &&
      other.pending == pending &&
      other.settling == settling &&
      other.failure == failure &&
      other.failedAction == failedAction &&
      other.lastAdvance == lastAdvance;

  @override
  int get hashCode => Object.hash(pending, settling, failure, failedAction, lastAdvance);

  @override
  String toString() =>
      'ConsoleState(pending: ${pending?.name}, settling: $settling, failure: $failure, '
      'failedAction: ${failedAction?.name}, lastAdvance: ${lastAdvance?.id})';
}

/// Um avanço como foi pedido: repeti-lo é mandar exatamente isto de novo.
@immutable
final class _AdvanceRequest {
  const _AdvanceRequest({
    required this.callAnother,
    required this.noShow,
    required this.requestId,
    required this.servingTicketId,
    required this.sentAt,
    required this.triedAt,
  });

  final bool callAnother;
  final bool noShow;
  final String requestId;

  /// Quem a tela mostrava na cadeira quando o barbeiro tocou.
  final String? servingTicketId;

  /// A primeira tentativa, de onde o app conta a janela de desfazer.
  final DateTime sentAt;

  /// O fim da última tentativa, de onde conta [ConsoleController.unansweredLifetime].
  final DateTime triedAt;

  _AdvanceRequest triedAgainAt(DateTime time) => _AdvanceRequest(
    callAnother: callAnother,
    noShow: noShow,
    requestId: requestId,
    servingTicketId: servingTicketId,
    sentAt: sentAt,
    triedAt: time,
  );
}

extension on Failure? {
  /// Se a falha quer dizer que o servidor pode ter aplicado o pedido sem a resposta chegar. No
  /// navegador, uma queda de rede chega como erro inesperado.
  bool get isNoAnswer => switch (this) {
    NetworkFailure() => true,
    UnexpectedFailure(:final cause) => cause is! FormatException,
    _ => false,
  };

  /// O servidor respondeu que deu certo, num formato que o app não entende: o pedido foi aplicado,
  /// e o app não sabe com qual resultado.
  bool get isUnreadableAnswer => switch (this) {
    UnexpectedFailure(:final cause) => cause is FormatException,
    _ => false,
  };
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

  /// Por quanto tempo o Desfazer fica em oferta quando o servidor não informa a janela da
  /// barbearia no resultado do avanço: o padrão dele (`undoWindowSec`). O servidor ainda tolera
  /// alguns segundos a mais pela demora da rede.
  static const undoWindow = Duration(seconds: 15);

  /// Por quanto tempo, depois da última tentativa, um avanço sem resposta ainda é repetido como o
  /// mesmo pedido. Depois disso o toque vale como intenção nova.
  static const unansweredLifetime = Duration(minutes: 2);

  /// Por quanto tempo, depois da última tentativa, o toque num botão que mudou de função ainda é
  /// reação à falha. Bem mais curto que [unansweredLifetime]: passado isso, é o barbeiro decidindo
  /// finalizar quem está na cadeira.
  static const repeatedTapLifetime = Duration(seconds: 15);

  Timer? _timer;
  Timer? _undoExpiry;

  /// Último avanço enviado que ficou sem resposta do servidor (falha de rede ou inesperada).
  _AdvanceRequest? _unanswered;

  /// O avanço em andamento.
  late _AdvanceRequest _advance;

  /// O avanço em andamento repete um pedido que tinha ficado sem resposta.
  bool _advanceRepeats = false;

  /// Depois de um avanço recusado porque a cadeira era outra, ou sem resposta: quem a tela mostrava
  /// na cadeira. Fica guardado até a tela mudar.
  ({String? servingTicketId})? _staleChair;

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
    () => _sendAdvance(callAnother: true, noShow: noShow),
    confirmed: _queueResolves,
    onAccepted: _rememberAdvance,
  );

  /// Finaliza o atendimento atual sem chamar ninguém (fila vazia, ou antes de uma pausa).
  Future<void> finishCurrent({bool noShow = false}) => _run<AdvanceResult>(
    noShow ? ConsoleAction.noShow : ConsoleAction.finish,
    () => _sendAdvance(callAnother: false, noShow: noShow),
    confirmed: _queueResolves,
    onAccepted: _rememberAdvance,
  );

  /// Se a fila já não tem mais o que mostrar sobre este avanço: ou a cadeira é a que ele deixou
  /// (vazia, se ele só finalizou), ou [_overtaken].
  bool _queueResolves(PublicQueue? queue, AdvanceResult result) =>
      queue?.servedBy(key.barberId)?.ticketId == result.called?.ticketId ||
      _overtaken(queue, result);

  /// Numa repetição, o resultado pode ser antigo. Se a cadeira não é nem a de quando o barbeiro
  /// tocou nem a que o avanço deixou, algo aconteceu depois (em outro aparelho, por exemplo). Se ela
  /// ainda é a de antes do toque, a fila só não chegou.
  bool _overtaken(PublicQueue? queue, AdvanceResult result) {
    if (!_advanceRepeats) return false;
    final chair = queue?.servedBy(key.barberId)?.ticketId;
    return chair != _advance.servingTicketId && chair != result.called?.ticketId;
  }

  /// Envia um avanço. Se o anterior ficou sem resposta (a rede caiu no meio), o toque seguinte repete
  /// exatamente aquele pedido em vez de fazer um novo: se o servidor já o tinha aplicado, devolve o
  /// mesmo resultado, e a fila não anda duas vezes por um toque que parecia ter falhado.
  ///
  /// Vale também por alguns segundos se a cadeira mudou desde o envio, mesmo que o comando agora seja
  /// outro: o botão que dizia "Próximo!" pode virar "Finalizar" quando a fila chega, e quem repete o
  /// toque ainda está reagindo à falha, não pedindo para finalizar quem acabou de ser chamado.
  Future<Result<AdvanceResult>> _sendAdvance({
    required bool callAnother,
    required bool noShow,
  }) async {
    final now = ref.read(clockProvider)();
    final kept = _unanswered;
    final repeats = kept != null && _sameIntent(kept, callAnother, noShow, now);
    final request =
        (repeats ? kept : null) ??
        _AdvanceRequest(
          callAnother: callAnother,
          noShow: noShow,
          requestId: ref.read(requestIdGeneratorProvider)(),
          servingTicketId: _servingTicketId,
          sentAt: now,
          triedAt: now,
        );
    _unanswered = request;
    _advance = request;
    _advanceRepeats = repeats;

    final outcome = noShow ? FinishOutcome.noShow : FinishOutcome.done;
    final result = request.callAnother
        ? await _repository.callNext(
            shopId: key.shopId,
            servingTicketId: request.servingTicketId,
            outcome: outcome,
            requestId: request.requestId,
          )
        : await _repository.finishCurrent(
            shopId: key.shopId,
            servingTicketId: request.servingTicketId,
            outcome: outcome,
            requestId: request.requestId,
          );
    // O barbeiro saiu da tela no meio do pedido: não há mais o que atualizar.
    if (!ref.mounted) return result;

    final failure = result.failureOrNull;
    final noAnswer = failure.isNoAnswer;
    // Com uma resposta clara do servidor, o pedido está encerrado.
    _unanswered = noAnswer ? request.triedAgainAt(ref.read(clockProvider)()) : null;
    final mayHaveAdvanced = noAnswer || failure.isUnreadableAnswer;
    if (mayHaveAdvanced) {
      // O servidor guarda um desfazer por barbeiro, e este pedido pode ter tomado o lugar do
      // anterior: o aviso que está na tela talvez já desfizesse outra coisa.
      _withdrawUndo();
    }
    if (mayHaveAdvanced || failure == const QueueRuleFailure(QueueErrorCode.servingChanged)) {
      _staleChair = (servingTicketId: request.servingTicketId);
    }
    return result;
  }

  /// Se o toque ainda é o pedido [kept], que ficou sem resposta, e não uma intenção nova.
  bool _sameIntent(_AdvanceRequest kept, bool callAnother, bool noShow, DateTime now) {
    if (kept.noShow != noShow) return false;
    final waited = now.difference(kept.triedAt);
    if (kept.callAnother == callAnother) return waited < unansweredLifetime;
    return waited < repeatedTapLifetime && _servingTicketId != kept.servingTicketId;
  }

  /// Desfaz o último "Próximo!", "Finalizar" ou "Não veio" deste barbeiro.
  ///
  /// Não espera a fila confirmar o avanço nem o descanso dos botões: quem percebe o engano na
  /// hora toca em "Desfazer" justamente nesse intervalo.
  Future<void> undoLast() {
    final advance = state.lastAdvance;
    if (_sending) {
      // Outro pedido ainda está a caminho. O toque já tirou o aviso da tela; ele volta, para o
      // barbeiro tentar de novo em vez de achar que desfez.
      if (advance != null) _offerUndo(advance.result, undoFor: advance.undoFor);
      return Future<void>.value();
    }
    _timer?.cancel();
    _timer = null;
    _confirmed = null;
    _staleChair = null;
    // O barbeiro mudou de assunto: um reenvio agora seria um replay de algo que ele já desfez.
    _unanswered = null;
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

  /// Quem a tela mostra na cadeira deste barbeiro. Vai junto com cada avanço: se o servidor vir
  /// outra pessoa lá, recusa em vez de finalizar quem o barbeiro não está vendo.
  String? get _servingTicketId => _queue?.servedBy(key.barberId)?.ticketId;

  /// Tira da fila alguém que ainda espera (desistiu, entrada de brincadeira). O servidor não
  /// desfaz isso: a tela pede confirmação antes de chamar.
  Future<void> removeTicket(WaitingTicket ticket) {
    // O descanso segura o toque repetido, e aqui o barbeiro acabou de confirmar num diálogo. Sem
    // isto, o que ele confirmou seria ignorado sem aviso.
    if (state.settling) {
      _timer?.cancel();
      _timer = null;
      state = state.settled();
    }
    if (!state.busy) _removingTicketId = ticket.ticketId;
    return _removeTicket(ticket);
  }

  /// Tira da tela o motivo de uma recusa, para quem já leu e não vai tentar de novo.
  void clearFailure() => state = ConsoleState(
    pending: state.pending,
    settling: state.settling,
    lastAdvance: state.lastAdvance,
  );

  /// O ticket do último pedido de remoção; a tela marca essa linha enquanto o pedido está em
  /// aberto (`pending == ConsoleAction.removeTicket`).
  String? get removingTicketId => _removingTicketId;
  String? _removingTicketId;

  Future<void> _removeTicket(WaitingTicket ticket) => _run<void>(
    ConsoleAction.removeTicket,
    () async {
      final result = await _repository.removeTicket(
        shopId: key.shopId,
        ticketId: ticket.ticketId,
      );
      return switch (result.failureOrNull) {
        // Só aqui essas recusas querem dizer que a pessoa saiu da espera.
        QueueRuleFailure(
          code: QueueErrorCode.ticketNotFound || QueueErrorCode.invalidTicketState,
        ) =>
          Err<void>(TicketGoneFailure(number: ticket.number, label: ticket.label)),
        _ => result,
      };
    },
    confirmed: (queue, _) => queue?.waitingTicket(ticket.ticketId) == null,
  );

  /// Fecha ou reabre a entrada de novos clientes. Quem já está na fila continua sendo atendido.
  Future<void> setAcceptingEntries({required bool accepting}) => _run<void>(
    accepting ? ConsoleAction.openEntries : ConsoleAction.closeEntries,
    () => _repository.setAcceptingEntries(shopId: key.shopId, accepting: accepting),
    confirmed: (queue, _) => queue != null && queue.entriesClosedByStaff == !accepting,
  );

  Future<void> _setStatus(ConsoleAction action, BarberStatus status) => _run<void>(
    action,
    () {
      _unanswered = null; // o barbeiro mudou de assunto: o próximo avanço é uma intenção nova
      return _repository.setBarberStatus(shopId: key.shopId, status: status);
    },
    // A fila pública só lista quem está em expediente: fora dela é "fora do expediente".
    confirmed: (queue, _) => (queue?.statusOf(key.barberId) ?? BarberStatus.off) == status,
  );

  void _rememberAdvance(AdvanceResult result) {
    // Fila vazia e ninguém na cadeira: o servidor não fez nada, então não há o que desfazer.
    if (result.called == null && result.finishedTicketId == null) return;

    // A janela conta de quando o servidor aplicou o avanço. O app não conhece esse instante e usa
    // o do envio, que é anterior: numa resposta atrasada (rede lenta, ou a repetição de um pedido
    // que tinha ficado sem resposta) oferece menos tempo, ou nada, em vez de um "Desfazer" que o
    // servidor já não aceita.
    final elapsed = ref.read(clockProvider)().difference(_advance.sentAt);
    final remaining = (result.undoWindow ?? undoWindow) - elapsed;
    // O servidor guarda um desfazer por barbeiro: o deste avanço substituiu o do anterior.
    _withdrawUndo();
    if (remaining <= Duration.zero) return;
    // Se algo aconteceu depois, o desfazer guardado no servidor já não é o deste avanço.
    if (_overtaken(_queue, result)) return;

    _offerUndo(result, undoFor: remaining);
    _undoExpiry = Timer(remaining, () {
      _undoExpiry = null;
      if (ref.mounted) _setAdvance(null);
    });
  }

  /// Põe (ou repõe) o aviso com "Desfazer" na tela. O prazo continua sendo o do avanço original.
  void _offerUndo(AdvanceResult result, {required Duration undoFor}) =>
      _setAdvance(AdvanceNotice(id: ++_notices, result: result, undoFor: undoFor));

  void _withdrawUndo() {
    _undoExpiry?.cancel();
    _undoExpiry = null;
    _setAdvance(null);
  }

  void _setAdvance(AdvanceNotice? advance) => state = ConsoleState(
    pending: state.pending,
    settling: state.settling,
    failure: state.failure,
    failedAction: state.failedAction,
    lastAdvance: advance,
  );

  void _fail(ConsoleAction action, Failure failure) {
    final advance = state.lastAdvance;
    state = ConsoleState(failure: failure, failedAction: action, lastAdvance: advance);
    if (action != ConsoleAction.undo || advance == null) return;

    // O toque em "Desfazer" já tirou o aviso da tela. Se o servidor recusou, não há mais o que
    // oferecer; se o pedido nem chegou a ser atendido (rede, por exemplo), o aviso volta para o
    // barbeiro tentar de novo enquanto houver prazo.
    if (failure is QueueRuleFailure) {
      _withdrawUndo();
    } else {
      _offerUndo(advance.result, undoFor: advance.undoFor);
    }
  }

  Future<void> _run<T>(
    ConsoleAction action,
    Future<Result<T>> Function() send, {
    required bool Function(PublicQueue? queue, T result) confirmed,
    void Function(T result)? onAccepted,
  }) async {
    if (state.busy) return;
    _staleChair = null;
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
        // A tela pode já ter mudado enquanto o servidor recusava.
        _onQueue(_queue);
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
    if (_confirmed?.call(queue) ?? false) return _settle();

    // O avanço foi recusado ou ficou sem resposta, e agora a tela mostra outra pessoa na cadeira. O
    // botão reaparece no mesmo lugar apontando para ela: fica inerte um instante, para o toque
    // repetido de quem tem pressa não agir sobre quem ele ainda não viu. O motivo da falha continua
    // à vista.
    final stale = _staleChair;
    if (stale != null && queue?.servedBy(key.barberId)?.ticketId != stale.servingTicketId) {
      _settle();
    }
  }

  void _settle() {
    _confirmed = null;
    _staleChair = null;
    state = state.settled(settling: true);
    _restartTimer(settleDelay, () => state = state.settled());
  }

  void _restartTimer(Duration duration, void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      if (ref.mounted) action();
    });
  }
}
