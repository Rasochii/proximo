import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/features/shop/data/shop_mapper.dart';
import 'package:proximo/features/shop/domain/shop.dart';
import 'package:proximo/features/shop/domain/shop_repository.dart';

final class FirestoreShopRepository implements ShopRepository {
  const FirestoreShopRepository(this._watch);

  final DocumentWatcher _watch;

  @override
  Stream<Shop?> watchShop(String shopId) => _watch(
    'shops/$shopId',
  ).map((json) => json == null ? null : ShopMapper.fromJson(shopId, json));
}
