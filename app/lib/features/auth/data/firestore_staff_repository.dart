import 'package:proximo/core/firebase/backend_ports.dart';
import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/auth/domain/staff_membership.dart';

final class FirestoreStaffRepository implements StaffRepository {
  const FirestoreStaffRepository(this._watch);

  final DocumentWatcher _watch;

  @override
  Stream<StaffMembership?> watchMembership(String uid) =>
      _watch('staff/$uid').map((json) => json == null ? null : membershipFromJson(json));

  /// Converte `staff/{uid}` (gravado pelo backend) para [StaffMembership].
  static StaffMembership membershipFromJson(JsonMap json) => StaffMembership(
    shopId: json.readString('shopId'),
    role: StaffRole.fromWire(json.readString('role')),
  );
}
