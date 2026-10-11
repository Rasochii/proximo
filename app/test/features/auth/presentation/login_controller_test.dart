import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/features/auth/presentation/auth_providers.dart';
import 'package:proximo/features/auth/presentation/login_controller.dart';

import '../../../helpers/fake_auth.dart';

const _email = 'ze@proximo.dev';
const _password = 'senha-de-teste';

void main() {
  late FakeAuthRepository auth;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthRepository(accounts: const {_email: (password: _password, user: barberZe)});
    addTearDown(auth.dispose);
    container = ProviderContainer.test(overrides: [authRepositoryProvider.overrideWithValue(auth)])
      // Mantém o controller vivo durante o teste, como a tela faria.
      ..listen(loginControllerProvider, (_, _) {});
  });

  LoginController controller() => container.read(loginControllerProvider.notifier);

  test('login válido termina sem falha e autentica o usuário', () async {
    await controller().signIn(email: _email, password: _password);

    expect(container.read(loginControllerProvider), const LoginState());
    expect(auth.currentUser, barberZe);
  });

  test('credenciais erradas deixam a falha no estado', () async {
    await controller().signIn(email: _email, password: 'errada');

    expect(container.read(loginControllerProvider), const LoginState(failure: PermissionFailure()));
    expect(auth.currentUser, isNull);
  });

  test('uma nova tentativa limpa a falha anterior', () async {
    await controller().signIn(email: _email, password: 'errada');
    await controller().signIn(email: _email, password: _password);

    expect(container.read(loginControllerProvider).failure, isNull);
  });

  test('um segundo toque durante o envio é ignorado', () async {
    final gate = Completer<void>();
    auth.signInGate = gate;

    final first = controller().signIn(email: _email, password: _password);
    expect(container.read(loginControllerProvider).submitting, isTrue);
    await controller().signIn(email: _email, password: _password);

    gate.complete();
    await first;

    expect(auth.signInAttempts, hasLength(1));
    expect(container.read(loginControllerProvider).submitting, isFalse);
  });
}
