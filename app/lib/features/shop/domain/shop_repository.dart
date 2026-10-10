import 'package:proximo/features/shop/domain/shop.dart';

/// Acesso somente leitura ao perfil público das barbearias.
// A escrita (cadastro) chega na fase F5, quando a interface ganha novos membros.
// ignore: one_member_abstracts
abstract interface class ShopRepository {
  /// Emite o perfil atualizado em tempo real; `null` se a barbearia não existir.
  Stream<Shop?> watchShop(String shopId);
}
