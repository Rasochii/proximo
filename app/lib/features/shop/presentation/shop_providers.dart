import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proximo/core/firebase/firebase_providers.dart';
import 'package:proximo/features/shop/data/firestore_shop_repository.dart';
import 'package:proximo/features/shop/domain/shop.dart';
import 'package:proximo/features/shop/domain/shop_repository.dart';

final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) => FirestoreShopRepository(ref.watch(documentWatcherProvider)),
);

/// Perfil da barbearia em tempo real. `null` = não existe.
final shopProvider = StreamProvider.autoDispose.family<Shop?, String>(
  (ref, shopId) => ref.watch(shopRepositoryProvider).watchShop(shopId),
);
