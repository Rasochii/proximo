import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/features/shop/domain/shop_slug.dart';

void main() {
  group('normalizeShopCode', () {
    test('ignora maiúsculas e espaços nas pontas', () {
      expect(normalizeShopCode('  Barbearia-do-Ze '), 'barbearia-do-ze');
    });

    test('troca espaços internos por hífen', () {
      expect(normalizeShopCode('barbearia do ze'), 'barbearia-do-ze');
    });

    test('aceita o link inteiro da fila, com ou sem #', () {
      expect(normalizeShopCode('https://proximo.app/b/barbearia-do-ze'), 'barbearia-do-ze');
      expect(normalizeShopCode('http://localhost:5000/#/b/barbearia-do-ze/'), 'barbearia-do-ze');
      expect(normalizeShopCode('proximo.app/b/barbearia-do-ze?origem=cartaz'), 'barbearia-do-ze');
    });

    test('campo vazio continua vazio', () {
      expect(normalizeShopCode('   '), isEmpty);
    });
  });

  group('isValidShopSlug', () {
    test('aceita letras minúsculas, números e hífens', () {
      expect(isValidShopSlug('barbearia-do-ze'), isTrue);
      expect(isValidShopSlug('corte10'), isTrue);
    });

    test('recusa acento, maiúscula, espaço, hífen nas pontas e código curto', () {
      for (final code in [
        'barbearia-do-zé',
        'Barbearia',
        'barbearia do ze',
        '-abc',
        'abc-',
        'ab',
      ]) {
        expect(isValidShopSlug(code), isFalse, reason: code);
      }
    });
  });
}
