import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tema Material 3 do Próximo!.
///
/// Identidade: cobre (navalha, cadeira de barbeiro antiga) sobre neutros quentes.
/// Números da fila usam algarismos tabulares para não "pularem" ao atualizar em tempo real.
abstract final class AppTheme {
  static const _seed = Color(0xFFB4532A);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    final text = base.textTheme;

    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        displayMedium: text.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radius),
          borderSide: BorderSide.none,
        ),
        // Sem borda em repouso, mas o foco e o erro precisam ser visíveis para quem usa teclado.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radius),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Insets.radius),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Insets.controlHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Insets.radius)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Insets.radiusLarge)),
      ),
    );
  }
}

/// Tokens de espaçamento e raio (escala de 4 pt).
abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const radius = 16.0;
  static const radiusLarge = 24.0;

  /// Altura dos botões principais e dos campos de texto.
  static const controlHeight = 56.0;

  /// Altura mínima de um alvo de toque (acessibilidade).
  static const touchTarget = 48.0;

  /// Largura máxima do conteúdo em coluna única (celular, formulários).
  static const maxContentWidth = 560.0;

  /// Largura máxima da página no layout de site (telas largas).
  static const maxSiteWidth = 1120.0;
}

/// Larguras em que o layout muda de forma.
abstract final class Breakpoints {
  /// A partir daqui a tela usa o layout de site: navegação no topo e conteúdo em colunas.
  /// Abaixo, vale a coluna única pensada para o celular de quem abre o QR Code.
  static const wide = 900.0;

  ///
  /// A largura é dividida pela escala de fonte do usuário: com letra em dobro, cabe metade do
  /// conteúdo, então a tela só conta como larga a partir do dobro da largura.
  static bool isWide(BuildContext context) {
    final textScale =
        MediaQuery.textScalerOf(context).scale(_referenceFontSize) / _referenceFontSize;
    return MediaQuery.sizeOf(context).width / math.max(1, textScale) >= wide;
  }

  static const _referenceFontSize = 16.0;
}
