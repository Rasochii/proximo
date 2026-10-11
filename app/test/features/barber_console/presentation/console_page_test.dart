import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/features/auth/domain/auth_repository.dart';

import '../../../helpers/fake_auth.dart';
import '../../../helpers/fixtures.dart';

const _shop = 'shops/barbearia-do-ze';
const _staff = 'staff/barbeiro-ze';
const _email = 'ze@proximo.dev';
const _password = 'senha-de-teste';

FakeDocuments seededDocs() => FakeDocuments({
  _shop: shopJson(),
  _staff: {'shopId': 'barbearia-do-ze', 'role': 'owner'},
});

FakeAuthRepository authWith({AppUser? signedInAs}) => FakeAuthRepository(
  signedInAs: signedInAs,
  accounts: const {_email: (password: _password, user: barberZe)},
);

Future<void> openConsole(WidgetTester tester, FakeDocuments docs, FakeAuthRepository auth) async {
  addTearDown(docs.dispose);
  addTearDown(auth.dispose);
  await pumpProximoApp(tester, watch: docs.watch, auth: auth);
  await tester.tap(find.text('Sou barbeiro'));
  await tester.pumpAndSettle();
}

Future<void> fillLogin(
  WidgetTester tester, {
  String email = _email,
  String password = _password,
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), email);
  await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), password);
}

void main() {
  group('sem login', () {
    testWidgets('mostra o formulário de entrada', (tester) async {
      await openConsole(tester, seededDocs(), authWith());

      expect(find.text('Entrar como barbeiro'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Senha'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
    });

    testWidgets('cliente com conta anônima também precisa entrar com a conta da equipe', (
      tester,
    ) async {
      const customer = AppUser(uid: 'cliente', isAnonymous: true);
      await openConsole(tester, seededDocs(), authWith(signedInAs: customer));

      expect(find.text('Entrar como barbeiro'), findsOneWidget);
    });

    testWidgets('login válido abre o console da barbearia do barbeiro', (tester) async {
      final auth = authWith();
      await openConsole(tester, seededDocs(), auth);

      await fillLogin(tester, email: '  $_email ');
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(auth.signInAttempts, [_email]);
      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.byTooltip('Conta'), findsOneWidget);
      expect(find.text('Entrar como barbeiro'), findsNothing);
    });

    testWidgets('senha errada mostra o erro e deixa tentar de novo', (tester) async {
      await openConsole(tester, seededDocs(), authWith());

      await fillLogin(tester, password: 'errada');
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);

      await fillLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
    });

    testWidgets('sem conexão mostra a mensagem de rede', (tester) async {
      final auth = authWith()..nextSignInFailure = const NetworkFailure();
      await openConsole(tester, seededDocs(), auth);

      await fillLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Sem conexão com o servidor. Verifique a internet.'), findsOneWidget);
    });

    /// Argumento `shouldSave` de cada encerramento do preenchimento automático.
    List<Object?> autofillSaves(WidgetTester tester) => [
      for (final call in tester.testTextInput.log)
        if (call.method == 'TextInput.finishAutofillContext') call.arguments,
    ];

    testWidgets('login certo oferece salvar a senha no gerenciador', (tester) async {
      await openConsole(tester, seededDocs(), authWith());

      await fillLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(autofillSaves(tester), [true]);
    });

    testWidgets('senha errada não é oferecida para salvar ao sair da tela', (tester) async {
      await openConsole(tester, seededDocs(), authWith());

      await fillLogin(tester, password: 'errada');
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar ao início'));
      await tester.pumpAndSettle();

      expect(autofillSaves(tester), [false]);
    });

    testWidgets('conta desativada orienta a falar com o dono', (tester) async {
      final auth = authWith()..nextSignInFailure = const AccountDisabledFailure();
      await openConsole(tester, seededDocs(), auth);

      await fillLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Esta conta está desativada. Fale com o dono da barbearia.'),
        findsOneWidget,
      );
    });

    testWidgets('campos vazios são apontados e o login não é chamado', (tester) async {
      final auth = authWith();
      await openConsole(tester, seededDocs(), auth);

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o e-mail.'), findsOneWidget);
      expect(find.text('Informe a senha.'), findsOneWidget);
      expect(auth.signInAttempts, isEmpty);
    });

    testWidgets('enquanto entra, o botão fica desabilitado', (tester) async {
      final gate = Completer<void>();
      final auth = authWith()..signInGate = gate;
      await openConsole(tester, seededDocs(), auth);

      await fillLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
    });

    testWidgets('depois de errar a senha, o campo continua com o foco e os dados digitados', (
      tester,
    ) async {
      await openConsole(tester, seededDocs(), authWith());

      await fillLogin(tester, password: 'errada');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
      final password = tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Senha'),
          matching: find.byType(EditableText),
        ),
      );
      expect(password.focusNode.hasFocus, isTrue);
      expect(password.controller.text, 'errada');
    });

    testWidgets('a senha pode ser mostrada e ocultada', (tester) async {
      await openConsole(tester, seededDocs(), authWith());
      EditableText password() => tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Senha'),
          matching: find.byType(EditableText),
        ),
      );

      expect(password().obscureText, isTrue);

      await tester.tap(find.byTooltip('Mostrar senha'));
      await tester.pump();
      expect(password().obscureText, isFalse);

      await tester.tap(find.byTooltip('Ocultar senha'));
      await tester.pump();
      expect(password().obscureText, isTrue);
    });

    testWidgets('o aviso de campo vazio some quando o campo é preenchido', (tester) async {
      await openConsole(tester, seededDocs(), authWith());

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o e-mail.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), _email);
      await tester.pumpAndSettle();

      expect(find.text('Informe o e-mail.'), findsNothing);
      expect(find.text('Informe a senha.'), findsOneWidget);
    });
  });

  group('com login', () {
    testWidgets('barbeiro já logado cai direto no console', (tester) async {
      await openConsole(tester, seededDocs(), authWith(signedInAs: barberZe));

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.text('Entrar como barbeiro'), findsNothing);
    });

    testWidgets('conta sem barbearia vê o aviso e pode entrar com outra conta', (tester) async {
      const stranger = AppUser(uid: 'sem-equipe', isAnonymous: false);
      await openConsole(tester, seededDocs(), authWith(signedInAs: stranger));

      expect(find.textContaining('não faz parte de nenhuma barbearia'), findsOneWidget);
      expect(find.byTooltip('Sair'), findsOneWidget);

      await tester.tap(find.text('Entrar com outra conta'));
      await tester.pumpAndSettle();

      expect(find.text('Entrar como barbeiro'), findsOneWidget);

      await fillLogin(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
    });

    testWidgets('quem é removido da equipe perde o console na hora', (tester) async {
      final docs = seededDocs();
      await openConsole(tester, docs, authWith(signedInAs: barberZe));
      expect(find.text('Barbearia do Zé'), findsOneWidget);

      docs.emit(_staff, null);
      await tester.pumpAndSettle();

      expect(find.textContaining('não faz parte de nenhuma barbearia'), findsOneWidget);
      expect(find.text('Barbearia do Zé'), findsNothing);
    });

    testWidgets('vínculo fora do formato vira erro, não console', (tester) async {
      final docs = FakeDocuments({
        _shop: shopJson(),
        _staff: {'role': 'owner'},
      });
      await openConsole(tester, docs, authWith(signedInAs: barberZe));

      expect(find.text('Algo deu errado. Tente de novo em instantes.'), findsOneWidget);
      expect(find.byTooltip('Sair'), findsOneWidget);
    });

    testWidgets('erro ao ler o vínculo oferece tentar de novo', (tester) async {
      final docs = seededDocs();
      await openConsole(tester, docs, authWith(signedInAs: barberZe));

      docs.fail(_staff, Exception('indisponível'));
      await tester.pumpAndSettle();

      expect(find.text('Algo deu errado. Tente de novo em instantes.'), findsOneWidget);

      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();

      expect(find.text('Barbearia do Zé'), findsOneWidget);
    });

    testWidgets('no console, sair fica no menu da conta e volta para o login', (tester) async {
      await openConsole(tester, seededDocs(), authWith(signedInAs: barberZe));

      expect(find.byTooltip('Sair'), findsNothing);
      await tester.tap(find.byTooltip('Conta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();

      expect(find.text('Entrar como barbeiro'), findsOneWidget);
    });
  });

  group('layout de site (tela larga)', () {
    testWidgets('console logado usa o cabeçalho do site, sem link na marca', (tester) async {
      useWideScreen(tester);
      await openConsole(tester, seededDocs(), authWith(signedInAs: barberZe));

      expect(find.text('Barbearia do Zé'), findsOneWidget);
      expect(find.byTooltip('Conta'), findsOneWidget);
      // Um esbarrão na marca não pode tirar o barbeiro do console.
      expect(find.text('Próximo!'), findsOneWidget);
      expect(find.byTooltip('Voltar ao início'), findsNothing);
    });

    testWidgets('estreitar a janela não apaga o login nem oferece salvar a senha', (tester) async {
      useWideScreen(tester);
      await openConsole(tester, seededDocs(), authWith());
      await fillLogin(tester, password: 'pela-metade');

      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();

      EditableText field(String label) => tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, label),
          matching: find.byType(EditableText),
        ),
      );
      expect(field('E-mail').controller.text, _email);
      expect(field('Senha').controller.text, 'pela-metade');
      expect(
        tester.testTextInput.log.where((call) => call.method == 'TextInput.finishAutofillContext'),
        isEmpty,
      );
    });
  });
}
