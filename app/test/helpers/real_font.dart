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
  final loader = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    final font = File('${artifacts.path}/material_fonts/roboto-$weight.ttf');
    loader.addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
  }
  await loader.load();
}
