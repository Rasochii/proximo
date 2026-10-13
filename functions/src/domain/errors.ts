/**
 * Erros de regra de negócio da fila.
 *
 * O domínio só conhece códigos estáveis; a camada Firebase traduz cada código
 * para um `HttpsError` e o app Flutter traduz para mensagens localizadas.
 */
export const DOMAIN_ERROR_CODES = [
  // Entrada inválida
  'invalid-argument',
  'invalid-name',
  'invalid-service',
  'invalid-schedule',
  // Estado da fila / horário
  'entries-closed',
  'closed-today',
  'not-open-yet',
  'closing-soon',
  'queue-full',
  'already-in-queue',
  // Tickets
  'ticket-not-found',
  'not-ticket-owner',
  'invalid-ticket-state',
  // Barbeiros
  'barber-not-found',
  'barber-not-on-shift',
  'barber-not-available',
  'finish-current-first',
  'nothing-to-finish',
  'serving-changed',
  // Desfazer
  'nothing-to-undo',
  'undo-expired',
  'undo-conflict',
  // Infra lógica
  'request-conflict',
  'rate-limited',
  'day-mismatch',
] as const;

export type DomainErrorCode = (typeof DOMAIN_ERROR_CODES)[number];

export class DomainError extends Error {
  constructor(
    readonly code: DomainErrorCode,
    message: string = DEFAULT_MESSAGES[code],
    readonly details?: Readonly<Record<string, unknown>>,
  ) {
    super(message);
    this.name = 'DomainError';
  }
}

/** Mensagens padrão em pt-BR (o app pode sobrescrever via i18n pelo `code`). */
export const DEFAULT_MESSAGES: Readonly<Record<DomainErrorCode, string>> = {
  'invalid-argument': 'Dados inválidos.',
  'invalid-name': 'Informe um nome válido (de 2 a 30 letras).',
  'invalid-service': 'Serviço indisponível.',
  'invalid-schedule': 'Horário de funcionamento inválido.',
  'entries-closed': 'A barbearia não está aceitando novas entradas agora.',
  'closed-today': 'A barbearia está fechada hoje.',
  'not-open-yet': 'A fila ainda não abriu.',
  'closing-soon': 'A barbearia está perto de fechar e não conseguiria te atender hoje.',
  'queue-full': 'A fila de hoje está cheia.',
  'already-in-queue': 'Você já está em uma fila.',
  'ticket-not-found': 'Ticket não encontrado.',
  'not-ticket-owner': 'Este ticket não pertence a você.',
  'invalid-ticket-state': 'Esta ação não é possível no estado atual do ticket.',
  'barber-not-found': 'Barbeiro não encontrado.',
  'barber-not-on-shift': 'Inicie o expediente antes de chamar clientes.',
  'barber-not-available': 'Seu expediente está pausado.',
  'finish-current-first': 'Finalize o atendimento atual primeiro.',
  'nothing-to-finish': 'Não há atendimento em andamento.',
  'serving-changed': 'A fila mudou. Confira quem está na cadeira.',
  'nothing-to-undo': 'Não há nada para desfazer.',
  'undo-expired': 'O tempo para desfazer acabou.',
  'undo-conflict': 'A fila mudou e não é mais possível desfazer.',
  'request-conflict': 'Requisição duplicada inválida.',
  'rate-limited': 'Muitas tentativas. Aguarde um pouco e tente de novo.',
  'day-mismatch': 'O dia da fila não corresponde ao dia atual.',
};

export function isDomainError(value: unknown): value is DomainError {
  return value instanceof DomainError;
}
