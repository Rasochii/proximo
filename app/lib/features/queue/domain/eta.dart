import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Previsão de início de atendimento calculada pelo servidor (simulação multi-barbeiro).
@immutable
sealed class Eta {
  const Eta();
}

/// Começa em ~[startsIn].
final class EstimatedEta extends Eta {
  const EstimatedEta(this.startsIn);

  final Duration startsIn;

  /// Faixa exibida ao usuário (±20%, entre 2 e 30 minutos para cada lado): prometer um número exato
  /// erra quase sempre; uma faixa honesta mantém a confiança.
  ({int min, int max}) get rangeInMinutes {
    final minutes = startsIn.inMinutes;
    if (minutes <= 0) return (min: 0, max: 0);
    final spread = math.min(30, math.max(2, (minutes * 0.2).round()));
    return (min: math.max(0, minutes - spread), max: minutes + spread);
  }

  @override
  bool operator ==(Object other) => other is EstimatedEta && other.startsIn == startsIn;

  @override
  int get hashCode => startsIn.hashCode;

  @override
  String toString() => 'EstimatedEta(${startsIn.inMinutes} min)';
}

/// Não daria tempo de ser atendido hoje.
final class BeyondClosingEta extends Eta {
  const BeyondClosingEta();
}

/// Sem barbeiro ativo para estimar.
final class UnknownEta extends Eta {
  const UnknownEta();
}
