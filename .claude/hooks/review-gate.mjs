// Trava de revisão (ADR 0008): o commit só passa se os revisores aprovaram o conteúdo que ele grava.
//
// - SubagentStart: guarda a impressão digital dos arquivos alterados quando um revisor começa.
// - SubagentStop: registra o veredito para os arquivos que não mudaram durante a revisão.
// - --pre-commit (.githooks/pre-commit): dentro do `git commit`, compara o que vai ser gravado com o que
//   foi aprovado. Qualquer código de saída diferente de zero barra o commit.
// - PreToolUse (Bash|PowerShell): não deixa o Claude desligar a trava. Código 2 = comando bloqueado.
//
// Quem decide é o review-rules.mjs.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { changedFiles, gitIn, readInput, ROOT } from './lib.mjs';
import {
  blockMessage,
  inReviewScope,
  isBypassCommand,
  isReviewer,
  parseVerdict,
  pendingReviews,
  recordReview,
  REMOVED,
  reportFromTranscript,
  REVIEWERS,
  scopeFor,
} from './review-rules.mjs';

// No fim de um agente, o código 2 significa "continue trabalhando". Lá a falha sai com 1 e só deixa de
// registrar a aprovação, que já é o lado seguro.
let refusalCode = 2;

if (process.argv[2] === '--pre-commit') preCommit(process.cwd());
if (process.argv.length > 2) block(`Argumento desconhecido: ${JSON.stringify(process.argv[2])}.`);

const input = await readInput();
const agent = input.agent_type ?? input.subagent_type;

if (input.hook_event_name?.startsWith('Subagent')) refusalCode = 1;

switch (input.hook_event_name) {
  case 'SubagentStart':
    if (isReviewer(agent)) {
      const repo = sessionRepo();
      writeJson(startFile(repo, input.agent_id), { agent, snapshot: snapshot(repo) });
    }
    break;
  case 'SubagentStop':
    if (isReviewer(agent)) finishReview(sessionRepo());
    break;
  case 'PreToolUse':
    if (isBypassCommand(input.tool_input?.command)) {
      block('Isso desliga a trava de revisão (ADR 0008). Quem pode pular a trava é uma pessoa, no terminal dela.');
    }
    break;
}

function preCommit(repo) {
  const staged = withoutMergedBlobs(repo, stagedBlobs(repo));
  const pending = pendingReviews(staged, loadRecords(repo));
  if (pending.length > 0) block(blockMessage(pending));
  process.exit(0);
}

/**
 * Num merge, o stage traz o outro branch inteiro. O que veio igual de lá não é trabalho deste commit
 * e passa pelo PR; a resolução de um conflito e qualquer edição feita durante o merge continuam aqui.
 */
function withoutMergedBlobs(repo, staged) {
  if (!existsSync(resolve(repo, gitPath(repo, 'MERGE_HEAD')))) return staged;
  const blobInMerge = (path) =>
    gitIn(repo, 'rev-parse', '--verify', '--quiet', `MERGE_HEAD:${path}`).stdout.trim() || REMOVED;
  return Object.fromEntries(Object.entries(staged).filter(([path, blob]) => blob !== blobInMerge(path)));
}

function sessionRepo() {
  const result = gitIn(input.cwd ?? ROOT, 'rev-parse', '--show-toplevel');
  return result.ok ? result.stdout.trim() : ROOT;
}

function finishReview(repo) {
  // Fica guardado: um revisor retomado termina de novo sem ter começado outra vez. Vale só para o que
  // não mudou desde o início dele; depois de uma correção, a aprovação pede um revisor novo.
  const started = readJson(startFile(repo, input.agent_id));
  if (!started) return; // a revisão começou antes de o hook existir: não dá para saber o que ela viu

  const before = scopeFor(agent, started.snapshot);
  const after = scopeFor(agent, snapshot(repo));
  const record = recordReview(before, after, parseVerdict(agentReport()));

  // Junta com o que já foi aprovado: o que saiu da lista de alterados deixa de contar.
  const previous = readJson(reviewFile(repo, agent)) ?? {};
  const kept = Object.fromEntries(Object.entries(previous).filter(([path]) => path in after && !(path in record)));
  writeJson(reviewFile(repo, agent), { ...kept, ...record });
}

/** O relatório final: o histórico do agente é a fonte mais segura; o evento só o traz em algumas versões. */
function agentReport() {
  const path = input.agent_transcript_path;
  if (typeof path === 'string' && existsSync(path)) return reportFromTranscript(readFileSync(path, 'utf8'));
  return input.last_assistant_message ?? null;
}

function loadRecords(repo) {
  return Object.fromEntries(REVIEWERS.map((r) => [r.agent, readJson(reviewFile(repo, r.agent)) ?? {}]));
}

/** `{ caminho: blob }` do código alterado e ainda não commitado, como está em disco. */
function snapshot(repo) {
  const files = changedFiles(repo, { renamedFrom: true });
  if (!files) block('Não consegui listar as alterações pelo git; a trava de revisão não pode decidir.');
  return Object.fromEntries(files.filter(inReviewScope).map((path) => [path, blobOf(repo, path)]));
}

/**
 * O id que o arquivo terá no git. Passa pelos filtros do repositório (fim de linha no Windows), então
 * compara direto com o que está em stage, e um `git stash pop` não invalida uma aprovação.
 */
function blobOf(repo, path) {
  if (!existsSync(join(repo, path))) return REMOVED;
  const result = gitIn(repo, 'hash-object', '--', path);
  if (!result.ok) block(`Não consegui calcular a impressão digital de ${path}.`);
  return result.stdout.trim();
}

/** `{ caminho: blob }` do que o commit vai gravar. Num arquivo renomeado, os dois nomes contam. */
function stagedBlobs(repo) {
  const result = gitIn(repo, 'diff', '--cached', '--raw', '--no-abbrev', '--no-renames', '-z');
  if (!result.ok) block('Não consegui ler o que está em stage; a trava de revisão não pode decidir.');
  const fields = result.stdout.split('\0');
  const staged = {};
  for (let i = 0; i + 1 < fields.length; i += 2) {
    const blob = fields[i].split(' ')[3];
    staged[fields[i + 1]] = /^0+$/.test(blob) ? REMOVED : blob;
  }
  return staged;
}

function gitPath(repo, name) {
  const result = gitIn(repo, 'rev-parse', '--git-path', name);
  if (!result.ok) block('Não consegui localizar o repositório; a trava de revisão não pode decidir.');
  return result.stdout.trim();
}

/** Fica dentro do .git: é por clone (e por worktree), nunca vai para o repositório. */
function stateDir(repo) {
  const dir = resolve(repo, gitPath(repo, 'proximo-revisao'));
  mkdirSync(dir, { recursive: true });
  return dir;
}

function startFile(repo, id) {
  return join(stateDir(repo), `inicio-${String(id).replace(/[^\w-]/g, '_')}.json`);
}

function reviewFile(repo, reviewer) {
  return join(stateDir(repo), `${reviewer}.json`);
}

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function writeJson(file, data) {
  writeFileSync(file, JSON.stringify(data, null, 2));
}

function block(message) {
  console.error(message);
  process.exit(refusalCode);
}
