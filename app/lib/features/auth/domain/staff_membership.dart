import 'package:meta/meta.dart';

/// Papel na equipe, como gravado pelo backend em `staff/{uid}`.
enum StaffRole {
  owner('owner'),
  barber('barber');

  const StaffRole(this.wire);

  final String wire;

  /// Papel desconhecido vira [barber]: o menor privilégio, sem travar o login.
  static StaffRole fromWire(String wire) =>
      values.firstWhere((role) => role.wire == wire, orElse: () => StaffRole.barber);
}

/// Vínculo do usuário logado com uma barbearia (`staff/{uid}`, ADR 0007).
///
/// Serve só para o app saber qual console abrir; quem autoriza cada ação é o servidor.
@immutable
final class StaffMembership {
  const StaffMembership({required this.shopId, required this.role});

  final String shopId;
  final StaffRole role;

  @override
  bool operator ==(Object other) =>
      other is StaffMembership && other.shopId == shopId && other.role == role;

  @override
  int get hashCode => Object.hash(shopId, role);

  @override
  String toString() => 'StaffMembership($shopId, ${role.wire})';
}

/// Leitura do vínculo de equipe do usuário logado.
// A escrita é sempre do servidor (cadastro na F5, convites na F6).
// ignore: one_member_abstracts
abstract interface class StaffRepository {
  /// Emite o vínculo em tempo real; `null` se o usuário não faz parte de nenhuma equipe.
  Stream<StaffMembership?> watchMembership(String uid);
}
