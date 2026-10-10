import { DomainError } from './errors';

export const NAME_MIN_LENGTH = 2;
export const NAME_MAX_LENGTH = 30;

/** Letras (qualquer idioma), acentos combinados, espaço, apóstrofo, ponto e hífen. Sem dígitos, URLs ou emojis. */
const ALLOWED_NAME = /^\p{L}[\p{L}\p{M}' .\-]*$/u;

export interface SanitizedName {
  /** Nome completo saneado (visível só para a equipe). */
  readonly displayName: string;
  /** Rótulo público minimizado (LGPD): primeiro nome + inicial do último sobrenome. */
  readonly label: string;
}

/**
 * Saneia o nome digitado pelo cliente.
 * @throws DomainError('invalid-name')
 */
export function sanitizeDisplayName(raw: unknown): SanitizedName {
  if (typeof raw !== 'string') throw new DomainError('invalid-name');

  const displayName = raw.normalize('NFC').replace(/\s+/gu, ' ').trim();
  const length = [...displayName].length;
  if (length < NAME_MIN_LENGTH || length > NAME_MAX_LENGTH || !ALLOWED_NAME.test(displayName)) {
    throw new DomainError('invalid-name');
  }
  return { displayName, label: toPublicLabel(displayName) };
}

function toPublicLabel(displayName: string): string {
  const words = displayName.split(' ').filter((word) => /\p{L}/u.test(word));
  const first = words[0] ?? displayName;
  if (words.length < 2) return first;
  const lastInitial = [...(words[words.length - 1] ?? '')][0]?.toLocaleUpperCase('pt-BR');
  return lastInitial ? `${first} ${lastInitial}.` : first;
}
