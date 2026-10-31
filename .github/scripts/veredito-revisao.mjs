// Transforma o veredito da revisão automática em check do PR (ADR 0008).
//
// O comentário geral da revisão termina com um marcador invisível:
//   <!-- veredito-revisao sha=<commit> bloqueante=sim|nao -->
// Sem marcador para o commit atual, o check falha: revisão que não terminou não aprova ninguém.
//
// A revisão pode errar. Quem discorda é o dono do repositório: ele comenta `/contestar <commit>` no PR
// e reexecuta só este job. Vale para aquele commit; um push novo volta a ser avaliado.
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const BOT = 'claude[bot]';

/** O veredito do bot para este commit: `'sim'`, `'nao'` ou `null`. Na dúvida entre dois, vale o `'sim'`. */
export function verdictFor(comments, sha) {
  const marker = new RegExp(`^<!--\\s*veredito-revisao\\s+sha=${sha}\\s+bloqueante=(sim|nao)\\s*-->$`);
  const found = comments
    .filter((comment) => comment.author === BOT)
    .map((comment) => marker.exec(comment.body.trim().split(/\r?\n/).at(-1).trim())?.[1])
    .filter(Boolean);
  return found.includes('sim') ? 'sim' : (found.at(-1) ?? null);
}

/** Comentário inline `[Crítico]` ou `[Alto]` neste commit, mesmo que o marcador diga o contrário. */
export function hasBlockingInline(inline, sha) {
  return inline.some(
    (comment) => comment.author === BOT && comment.commit === sha && /^[\s*_]*\[(crítico|alto)\]/iu.test(comment.body),
  );
}

/** Se o dono do repositório contestou exatamente este commit (hash completo ou com 7+ caracteres). */
export function isContested(comments, sha, owner) {
  return comments
    .filter((comment) => comment.author === owner)
    .flatMap((comment) => [...comment.body.matchAll(/^\/contestar\s+([0-9a-f]{7,40})\s*$/gm)])
    .some((match) => sha.startsWith(match[1]));
}

/** Decide o check. Devolve `{ ok, message }`. */
export function decide({ scope, relevant, comments, inline, sha, owner }) {
  if (scope !== 'success') return { ok: false, message: 'Não deu para saber se o PR precisa de revisão.' };
  if (relevant === 'false') return { ok: true, message: 'O PR não mexe em código revisado: nada a conferir.' };
  if (isContested(comments, sha, owner)) return { ok: true, message: `Commit contestado por ${owner}.` };

  const blocked = 'A revisão encontrou achado Crítico ou Alto; veja os comentários no PR.';
  if (hasBlockingInline(inline, sha)) return { ok: false, message: blocked };

  const verdict = verdictFor(comments, sha);
  if (verdict === 'nao') return { ok: true, message: 'A revisão não encontrou nada Crítico ou Alto.' };
  if (verdict === 'sim') return { ok: false, message: blocked };
  return { ok: false, message: `A revisão não publicou veredito para o commit ${sha}.` };
}

function list(path, jq) {
  return execFileSync('gh', ['api', path, '--paginate', '--jq', jq], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function main() {
  const { REPO, PR, SHA, OWNER, ESCOPO, RELEVANTE } = process.env;
  const comments = list(`repos/${REPO}/issues/${PR}/comments`, '.[] | {author: .user.login, body: .body}');
  const inline = list(
    `repos/${REPO}/pulls/${PR}/comments`,
    // `original_commit_id`: o `commit_id` acompanha o PR e faria um achado antigo valer para o commit novo.
    '.[] | {author: .user.login, body: .body, commit: .original_commit_id}',
  );

  const { ok, message } = decide({ scope: ESCOPO, relevant: RELEVANTE, comments, inline, sha: SHA, owner: OWNER });
  console.log(`${ok ? '::notice' : '::error'} title=Veredito da revisão::${message}`);
  process.exit(ok ? 0 : 1);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) main();
