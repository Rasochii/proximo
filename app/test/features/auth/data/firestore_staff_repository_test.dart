import 'package:flutter_test/flutter_test.dart';
import 'package:proximo/features/auth/data/firestore_staff_repository.dart';
import 'package:proximo/features/auth/domain/staff_membership.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('membershipFromJson', () {
    test('converte o vínculo gravado pelo backend', () {
      expect(
        FirestoreStaffRepository.membershipFromJson({
          'shopId': 'barbearia-do-ze',
          'role': 'owner',
          'updatedAt': 1791656643259,
        }),
        const StaffMembership(shopId: 'barbearia-do-ze', role: StaffRole.owner),
      );
    });

    test('papel desconhecido vira barbeiro, o menor privilégio', () {
      final membership = FirestoreStaffRepository.membershipFromJson({
        'shopId': 'barbearia-do-ze',
        'role': 'gerente',
      });

      expect(membership.role, StaffRole.barber);
    });

    test('rejeita vínculo sem barbearia', () {
      expect(
        () => FirestoreStaffRepository.membershipFromJson({'role': 'owner'}),
        throwsFormatException,
      );
    });
  });

  group('watchMembership', () {
    test('lê staff/{uid} e acompanha mudanças', () async {
      final docs = FakeDocuments({
        'staff/barbeiro-ze': {'shopId': 'barbearia-do-ze', 'role': 'barber'},
      });
      addTearDown(docs.dispose);
      final repository = FirestoreStaffRepository(docs.watch);

      final emitted = <StaffMembership?>[];
      final subscription = repository.watchMembership('barbeiro-ze').listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      docs.emit('staff/barbeiro-ze', null);
      await pumpEventQueue();

      expect(emitted, [
        const StaffMembership(shopId: 'barbearia-do-ze', role: StaffRole.barber),
        null,
      ]);
    });

    test('usuário sem vínculo recebe null', () async {
      final docs = FakeDocuments();
      addTearDown(docs.dispose);

      expect(await FirestoreStaffRepository(docs.watch).watchMembership('cliente').first, isNull);
    });
  });
}
