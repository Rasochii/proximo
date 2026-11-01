import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/core/error/failure.dart';
import 'package:proximo/core/error/queue_error_code.dart';
import 'package:proximo/core/l10n/failure_messages.dart';
import 'package:proximo/l10n/gen/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('pt'));

  test('"a pessoa já saiu" só aparece com a falha própria da remoção', () {
    expect(
      l10n.failureMessage(const TicketGoneFailure(number: 2, label: 'Lucas M.')),
      'Nº 2 · Lucas M. não está mais esperando.',
    );
  });

  test('sem saber qual foi a ação, os códigos de ticket viram a mensagem genérica', () {
    for (final code in [QueueErrorCode.ticketNotFound, QueueErrorCode.invalidTicketState]) {
      expect(l10n.failureMessage(QueueRuleFailure(code)), l10n.genericError);
    }
  });
}
