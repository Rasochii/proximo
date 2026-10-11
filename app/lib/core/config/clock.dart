import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relógio do app. Existe para os testes poderem dizer que horas são.
///
/// É o relógio do aparelho: serve para comparar com prazos que o servidor calculou (como a
/// validade da fila pública), nunca para decidir regra de fila.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
