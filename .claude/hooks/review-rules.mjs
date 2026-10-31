// Regras da trava de revisão (ADR 0008). Só decisões, sem I/O: quem lê arquivos e o git é o
// review-gate.mjs. Assim dá para testar cada regra sem subir um agente de verdade.

export const REMOVED = '<removido>';

/** Quem precisa aprovar o quê. O workflow da revisão usa esta mesma lista. */
export const REVIEWERS = [
  {
    agent: 'flutter-reviewer',
    matches: (p) => p.startsWith('app/'),
  },
  {
    agent: 'ux-a11y-reviewer',
    matches: (p) =>
      /^app\/lib\/.*(_page|_view)\.dart$/.test(p) ||
      /^app\/lib\/.*\/widgets\//.test(p) ||
      p.startsWith('app/lib/core/theme/') ||
      p === 'app/lib/l10n/app_pt.arb',
  },
  {
    agent: 'backend-reviewer',
    matches: (p) =>
      p.startsWith('functions/') ||
      p === 'firebase.json' ||
      p === 'firestore.rules' ||
      p === 'firestore.indexes.json',
  },
];

export const isReviewer = (agent) => REVIEWERS.some((r) => r.agent === agent);

/** Só o que algum revisor precisa ver entra na conta da trava. */
export const inReviewScope = (path) => REVIEWERS.some((r) => r.matches(path));

/**
 * Se o comando desliga a trava: `git commit` que pula o hook, ou git mudando para onde os hooks
 * apontam. Pular é direito de uma pessoa, no terminal dela. Isto segura o engano, não a má-fé; contra
 * ela existem as regras no GitHub.
 */
export function isBypassCommand(command) {
  const text = String(command ?? '');
  const skipsHook = /\bgit\b[\s\S]*\scommit\b[\s\S]*--no-v|\bgit\b[^\n;&|]*\scommit\b[^\n;&|]*?\s-[a-z]*n[a-z]*(?![a-z-])/i; // o git aceita --no-ver
  const movesHooks = /\bgit\b(?!\s+config\s+--get)[^\n;&|]*\bcore\.hookspath/i; // chave de config não tem caixa
  return skipsHook.test(`${text} `) || movesHooks.test(text);
}

/** O veredito é a última linha com texto do relatório; se ela não for um veredito, não houve veredito. */
export function parseVerdict(report) {
  const lines = String(report ?? '')
    .split(/\r?\n/)
    .map((line) => line.replace(/[*#>`]/g, '').trim())
    .filter(Boolean);
  return /^VEREDITO:\s*(aprovado|corrigir)$/i.exec(lines.at(-1) ?? '')?.[1].toLowerCase() ?? null;
}

/**
 * O relatório final no histórico (JSONL) de um agente: a última mensagem dele. O relatório pode ser
 * texto comum ou a entrega pela ferramenta `SubagentHandback`, que é o que o Claude Code usa em
 * agentes em segundo plano. Se a última mensagem não tiver texto, ele foi cortado: não há relatório,
 * e um veredito anterior não vale para o que veio depois.
 */
export function reportFromTranscript(jsonl) {
  for (const line of String(jsonl ?? '').trim().split(/\r?\n/).reverse()) {
    let message;
    try {
      ({ message } = JSON.parse(line));
    } catch {
      continue; // linha incompleta
    }
    if (message?.role !== 'assistant') continue;
    return [message.content].flat().map(partText).join('\n').trim() || null;
  }
  return null;
}

function partText(part) {
  if (typeof part === 'string') return part;
  if (part?.type === 'tool_use') return part.name === 'SubagentHandback' ? (part.input?.message ?? '') : '';
  return part?.text ?? '';
}

/** Os arquivos que um revisor precisa ver: `{ caminho: blob }`. */
export function scopeFor(agent, blobs) {
  const reviewer = REVIEWERS.find((r) => r.agent === agent);
  return Object.fromEntries(Object.entries(blobs).filter(([path]) => reviewer?.matches(path)));
}

/**
 * Registra o fim de uma revisão. Só vale para arquivos que não mudaram enquanto o revisor trabalhava:
 * o que mudou no meio do caminho ele não viu.
 */
export function recordReview(before, after, verdict) {
  const record = {};
  for (const [path, hash] of Object.entries(after)) {
    if (before[path] === hash) record[path] = { hash, verdict: verdict ?? 'sem-veredito' };
  }
  return record;
}

const REASONS = {
  nunca: 'ainda não foi revisado',
  mudou: 'não é o conteúdo que foi revisado',
  corrigir: 'o revisor pediu correção',
  'sem-veredito': 'o revisor não deu veredito',
};

/**
 * O que ainda impede o commit.
 * - `staged`: `{ caminho: blob }` do que o commit vai gravar.
 * - `records`: `{ agente: { caminho: { hash, verdict } } }`.
 * Devolve `[{ agent, path, reason }]`; lista vazia libera.
 */
export function pendingReviews(staged, records) {
  const pending = [];
  for (const { agent } of REVIEWERS) {
    for (const [path, hash] of Object.entries(scopeFor(agent, staged))) {
      const entry = records[agent]?.[path];
      const reason = !entry
        ? REASONS.nunca
        : entry.hash !== hash
          ? REASONS.mudou
          : entry.verdict === 'aprovado'
            ? null
            : (REASONS[entry.verdict] ?? REASONS['sem-veredito']);
      if (reason) pending.push({ agent, path, reason });
    }
  }
  return pending;
}

function reviewerLines(agent, items) {
  return [
    `- ${agent}:`,
    ...items.slice(0, 12).map((p) => `    ${p.path}: ${p.reason}`),
    ...(items.length > 12 ? [`    … e mais ${items.length - 12} arquivo(s)`] : []),
  ];
}

/** Mensagem do commit barrado. */
export function blockMessage(pending) {
  const agents = [...new Set(pending.map((p) => p.agent))];
  const lines = agents.flatMap((agent) =>
    reviewerLines(
      agent,
      pending.filter((p) => p.agent === agent),
    ),
  );
  return [
    'Commit barrado pela trava de revisão (.claude/hooks/review-gate.mjs, ADR 0008).',
    ...lines,
    '',
    'Chame esses revisores com o conteúdo final e corrija o que eles apontarem como Crítico ou Alto.',
    'Se um revisor estiver errado, mostre a evidência a ele numa nova revisão ou peça ao usuário para',
    'decidir. Uma pessoa pode pular a trava no terminal dela, com git commit --no-verify; o Claude não.',
  ].join('\n');
}
