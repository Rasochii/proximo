// Utilitários compartilhados pelos hooks do Claude Code deste projeto.
// Escritos em Node (já é pré-requisito do projeto) para funcionarem igual no Windows, macOS e Linux.
import { spawnSync } from 'node:child_process';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Raiz do repositório. */
export const ROOT = process.env.CLAUDE_PROJECT_DIR
  ? resolve(process.env.CLAUDE_PROJECT_DIR)
  : resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Lê o JSON que o Claude Code envia pelo stdin. */
export async function readInput() {
  let raw = '';
  for await (const chunk of process.stdin) raw += chunk;
  try {
    return JSON.parse(raw || '{}');
  } catch {
    return {};
  }
}

/** Caminho relativo à raiz com "/" (o Windows usa "\"); null se estiver fora do projeto. */
export function toRepoPath(filePath) {
  if (typeof filePath !== 'string' || filePath.length === 0) return null;
  const abs = isAbsolute(filePath) ? filePath : resolve(ROOT, filePath);
  const rel = relative(ROOT, abs);
  if (rel === '' || rel.startsWith('..') || isAbsolute(rel)) return null;
  return rel.split(sep).join('/');
}

/** Executa um comando via shell (necessário no Windows para flutter.bat / npm.cmd). */
export function run(command, cwd = ROOT) {
  const result = spawnSync(command, {
    cwd,
    shell: true,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
    env: { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1' },
  });
  const stdout = result.stdout ?? '';
  const output = `${stdout}${result.stderr ?? ''}${result.error ? `\n${result.error.message}` : ''}`;
  return { ok: result.status === 0, stdout, output };
}

/** Executa o git sem shell (git.exe existe em todas as plataformas; evita problemas de aspas e de %). */
export function git(...args) {
  return gitIn(ROOT, ...args);
}

/** O mesmo, em outro diretório (uma worktree, por exemplo). */
export function gitIn(cwd, ...args) {
  const result = spawnSync('git', args, { cwd, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  return { ok: result.status === 0, stdout: result.stdout ?? '' };
}

/** Comando inexistente na máquina (ex.: Flutter não instalado) — não deve bloquear o Claude. */
export function isMissingCommand(output) {
  return (
    /not recognized as an internal or external command|command not found|ENOENT|não é reconhecido/i.test(output) ||
    /^\/bin\/sh: \d+: \S+: not found/m.test(output)
  );
}

/** Últimas linhas de uma saída longa, para não inundar o contexto. */
export function tail(text, lines = 60) {
  const all = text.trimEnd().split(/\r?\n/);
  return all.length <= lines ? all.join('\n') : [`… (${all.length - lines} linhas omitidas)`, ...all.slice(-lines)].join('\n');
}

export const GENERATED_DART = /\.(g|freezed|gr|mocks)\.dart$/;
export const L10N_GEN_DIR = 'app/lib/l10n/gen/';

/**
 * Arquivos com mudanças não commitadas (caminhos relativos à raiz, com "/"). Com `-z` o git não
 * escapa acentos nem espaços. Com `renamedFrom`, um arquivo renomeado aparece também pelo nome antigo.
 */
export function changedFiles(root = ROOT, { renamedFrom = false } = {}) {
  const status = gitIn(root, 'status', '--porcelain=v1', '-z', '-uall');
  if (!status.ok) return null;
  const fields = status.stdout.split('\0').filter(Boolean);
  const files = [];
  for (let i = 0; i < fields.length; i += 1) {
    const [x, y] = fields[i];
    files.push(fields[i].slice(3));
    if (x === 'R' || x === 'C' || y === 'R' || y === 'C') {
      i += 1;
      if (renamedFrom) files.push(fields[i]);
    }
  }
  return files;
}

/** Conta mudanças por área do monorepo. */
export function countByArea(files) {
  const counts = { app: 0, functions: 0, outros: 0 };
  for (const file of files) {
    if (file.startsWith('.claude/.cache/')) continue;
    if (file.startsWith('app/')) counts.app += 1;
    else if (file.startsWith('functions/') || file === 'firestore.rules') counts.functions += 1;
    else counts.outros += 1;
  }
  return counts;
}

/**
 * Fase atual segundo a tabela "Roadmap" do README: a primeira 🚧; se não houver, a primeira ⏳.
 * Retorna { id: 'F2', title: '...', status: '🚧 esqueleto pronto' } ou null.
 */
export function currentPhase(readme) {
  const rows = [...readme.matchAll(/^\|\s*(F\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$/gm)].map((m) => ({
    id: m[1],
    title: m[2],
    status: m[3],
  }));
  return rows.find((r) => r.status.includes('🚧')) ?? rows.find((r) => r.status.includes('⏳')) ?? null;
}

export const VERIFY_CACHE = '.claude/.cache/verify.json';
