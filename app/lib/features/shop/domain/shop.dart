import 'package:meta/meta.dart';

/// Dias da semana na mesma ordem e chave usadas pelo backend (`sun`…`sat`).
enum Weekday {
  sunday('sun'),
  monday('mon'),
  tuesday('tue'),
  wednesday('wed'),
  thursday('thu'),
  friday('fri'),
  saturday('sat');

  const Weekday(this.key);

  final String key;

  /// Converte `DateTime.weekday` (1 = segunda … 7 = domingo).
  static Weekday fromDateTime(DateTime date) => values[date.weekday % 7];
}

/// Período de funcionamento "HH:mm"–"HH:mm". As lacunas entre períodos são os intervalos fixos.
@immutable
final class OpeningInterval {
  const OpeningInterval({required this.start, required this.end});

  final String start;
  final String end;

  @override
  bool operator ==(Object other) =>
      other is OpeningInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start–$end';
}

@immutable
final class ShopService {
  const ShopService({
    required this.id,
    required this.name,
    required this.defaultDurationMin,
    required this.active,
  });

  final String id;
  final String name;
  final int defaultDurationMin;
  final bool active;
}

/// Perfil público da barbearia (`shops/{shopId}`). O id do documento é o próprio slug.
@immutable
final class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.timezone,
    required this.services,
    required this.weeklySchedule,
  });

  final String id;
  final String name;
  final String timezone;
  final List<ShopService> services;
  final Map<Weekday, List<OpeningInterval>> weeklySchedule;

  List<ShopService> get activeServices => [
    for (final service in services)
      if (service.active) service,
  ];

  List<OpeningInterval> scheduleFor(Weekday day) => weeklySchedule[day] ?? const [];
}
