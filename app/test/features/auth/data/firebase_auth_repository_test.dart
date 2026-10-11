import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/features/auth/data/firebase_auth_repository.dart';

void main() {
  group('failureFromAuthCode', () {
    test('credenciais erradas, de qualquer tipo, viram a mesma falha', () {
      for (final code in [
        'invalid-credential',
        'wrong-password',
        'user-not-found',
        'invalid-email',
      ]) {
        expect(
          FirebaseAuthRepository.failureFromAuthCode(code),
          const PermissionFailure(),
          reason: code,
        );
      }
    });

    test('sem rede vira falha de rede', () {
      expect(
        FirebaseAuthRepository.failureFromAuthCode('network-request-failed'),
        const NetworkFailure(),
      );
    });

    test('excesso de tentativas pede para esperar, em vez de tentar de novo', () {
      expect(
        FirebaseAuthRepository.failureFromAuthCode('too-many-requests'),
        const QueueRuleFailure(QueueErrorCode.rateLimited),
      );
    });

    test('conta desativada tem falha própria, que não sugere tentar de novo', () {
      expect(
        FirebaseAuthRepository.failureFromAuthCode('user-disabled'),
        const AccountDisabledFailure(),
      );
    });

    test('código desconhecido vira falha inesperada', () {
      expect(
        FirebaseAuthRepository.failureFromAuthCode('internal-error'),
        isA<UnexpectedFailure>(),
      );
    });
  });
}
