import 'dart:io';

import 'package:flutter/services.dart';

/// Carrega a Roboto que vem com o Flutter.
///
/// A fonte padrão dos testes desenha cada letra como um quadrado e exagera a altura do texto: para
/// conferir o que cabe na tela, só a fonte de verdade serve. Ela passa a valer para o arquivo de
/// teste inteiro, então use num arquivo próprio.
Future<void> loadRoboto() async {
  // O executável dos testes fica em bin/cache/artifacts/engine/<plataforma>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final fonts = Directory('${artifacts.path}/material_fonts').listSync().whereType<File>();
  final loader = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    // A caixa do nome do arquivo muda de uma plataforma para outra.
    final name = 'roboto-$weight.ttf';
    final font = fonts.firstWhere(
      (file) => file.uri.pathSegments.last.toLowerCase() == name,
      orElse: () => throw StateError('$name não está em material_fonts: ${fonts.toList()}'),
    );
    loader.addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
  }
  await loader.load();
}
