/// Utilitários para ler dados vindos do Firestore e das Cloud Functions com segurança de tipos.
///
/// Os SDKs devolvem mapas com tipos diferentes por plataforma (`Map<String, dynamic>`,
/// `Map<Object?, Object?>`); tudo é normalizado para [JsonMap] e lido com validação.
/// Dados fora do formato esperado viram [FormatException] — nunca um cast silencioso.
library;

typedef JsonMap = Map<String, Object?>;

/// Converte recursivamente qualquer mapa/lista vindo de um SDK em [JsonMap]/`List<Object?>`.
Object? normalizeJson(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final entry in map.entries) '${entry.key}': normalizeJson(entry.value),
  },
  final List<Object?> list => [for (final item in list) normalizeJson(item)],
  _ => value,
};

JsonMap asJsonMap(Object? value, [String context = 'documento']) {
  final normalized = normalizeJson(value);
  if (normalized is JsonMap) return normalized;
  throw FormatException('Esperava um objeto em $context, veio ${value.runtimeType}.');
}

extension JsonReader on JsonMap {
  String readString(String key) => _read<String>(key);

  String? readStringOrNull(String key) => _readOrNull<String>(key);

  int readInt(String key) => _read<num>(key).toInt();

  int? readIntOrNull(String key) => _readOrNull<num>(key)?.toInt();

  bool readBool(String key) => _read<bool>(key);

  JsonMap readMap(String key) => asJsonMap(this[key], key);

  JsonMap? readMapOrNull(String key) => this[key] == null ? null : readMap(key);

  /// Lista de objetos convertidos por [parse].
  List<T> readList<T>(String key, T Function(JsonMap item) parse) {
    final value = this[key] ?? const <Object?>[];
    if (value is! List<Object?>) throw FormatException('Campo "$key" deveria ser uma lista.');
    return [for (final item in value) parse(asJsonMap(item, key))];
  }

  T _read<T>(String key) {
    final value = this[key];
    if (value is T) return value;
    throw FormatException('Campo "$key" deveria ser $T, veio ${value.runtimeType}.');
  }

  T? _readOrNull<T>(String key) => this[key] == null ? null : _read<T>(key);
}
