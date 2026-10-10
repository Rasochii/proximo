import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/features/shop/data/shop_mapper.dart';
import 'package:proximo/features/shop/domain/shop.dart';

import '../../../helpers/fixtures.dart';

void main() {
  test('converte o perfil público da barbearia', () {
    final shop = ShopMapper.fromJson('barbearia-do-ze', shopJson());

    expect(shop.name, 'Barbearia do Zé');
    expect(shop.services, hasLength(2));
    expect(shop.activeServices.map((s) => s.id), ['corte']);
    expect(shop.scheduleFor(Weekday.monday), const [
      OpeningInterval(start: '09:00', end: '12:00'),
      OpeningInterval(start: '13:00', end: '19:00'),
    ]);
    // Dias ausentes no documento = fechado.
    expect(shop.scheduleFor(Weekday.saturday), isEmpty);
  });

  test('Weekday.fromDateTime segue a convenção do backend (domingo = sun)', () {
    expect(Weekday.fromDateTime(DateTime(2026, 10, 11)), Weekday.sunday);
    expect(Weekday.fromDateTime(DateTime(2026, 10, 10)), Weekday.saturday);
  });

  test('rejeita documento sem nome', () {
    expect(() => ShopMapper.fromJson('x', {'services': <Object?>[]}), throwsFormatException);
  });
}
