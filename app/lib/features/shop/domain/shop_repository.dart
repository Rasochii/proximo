import 'package:proximo/features/shop/domain/shop.dart';

/// Acesso somente leitura ao perfil público das barbearias.
// A escrita (cadastro) chega na fase F5, via callable.
abstract interface class ShopRepository {
  /// Emite o perfil atualizado em tempo real; `null` se a barbearia não existir.
  Stream<Shop?> watchShop(String shopId);
}
