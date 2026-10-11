/// Código da barbearia (slug): o final do link da fila, como em `…/b/barbearia-do-ze`.
///
/// Mesma regra do backend em `functions/src/domain/shop.ts`: de 3 a 48 caracteres, só letras
/// minúsculas, números e hífens, sem hífen nas pontas.
final _slugPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{1,46}[a-z0-9])$');

bool isValidShopSlug(String value) => _slugPattern.hasMatch(value);

/// Transforma o que a pessoa digitou ou colou num candidato a código: ignora maiúsculas e
/// espaços nas pontas, troca espaços por hífen e, se vier o link inteiro, fica só com o que
/// vem depois de `/b/`.
///
/// O resultado ainda precisa passar por [isValidShopSlug].
String normalizeShopCode(String input) {
  var text = input.trim().toLowerCase();
  final marker = text.lastIndexOf('/b/');
  if (marker >= 0) text = text.substring(marker + '/b/'.length);
  text = text.split(RegExp('[?#]')).first;
  return text.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'\s+'), '-');
}
