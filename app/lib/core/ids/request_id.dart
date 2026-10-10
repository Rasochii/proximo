import 'package:uuid/uuid.dart';

/// Gera o `requestId` (UUID v4) que torna cada comando idempotente no backend (ADR 0004).
/// É uma função para facilitar testes determinísticos.
typedef RequestIdGenerator = String Function();

const _uuid = Uuid();

String uuidV4RequestId() => _uuid.v4();
