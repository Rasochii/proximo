import 'package:proximo/core/json/json.dart';
import 'package:proximo/features/shop/domain/shop.dart';

/// Converte `shops/{shopId}` (formato em `functions/src/domain/types.ts`) para [Shop].
abstract final class ShopMapper {
  static Shop fromJson(String id, JsonMap json) {
    final schedule = json.readMapOrNull('schedule') ?? const <String, Object?>{};
    return Shop(
      id: id,
      name: json.readString('name'),
      timezone: json.readStringOrNull('timezone') ?? 'America/Sao_Paulo',
      services: json.readList('services', _service),
      weeklySchedule: {
        for (final day in Weekday.values) day: schedule.readList(day.key, _interval),
      },
    );
  }

  static ShopService _service(JsonMap json) => ShopService(
    id: json.readString('id'),
    name: json.readString('name'),
    defaultDurationMin: json.readInt('defaultDurationMin'),
    active: json['active'] != false,
  );

  static OpeningInterval _interval(JsonMap json) =>
      OpeningInterval(start: json.readString('start'), end: json.readString('end'));
}
