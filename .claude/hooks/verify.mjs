// Stop: antes de o Claude encerrar, roda a verificação das áreas com mudanças não commitadas.
// - Só roda o que mudou (app/ e/ou functions/).
// - Guarda uma impressão digital dos arquivos: não repete verificação já feita (sucesso ou falha)
//   para o mesmo conteúdo, o que também evita loop infinito se o Claude não conseguir corrigir.
// - Registra o último resultado em .claude/.cache/verify.json (lido pela status line e pelo SessionStart).
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

import {
  changedFiles,
  GENERATED_DART,
  isMissingCommand,
  L10N_GEN_DIR,
  readInput,
  ROOT,
  run,
  tail,
  VERIFY_CACHE,
} from './lib.mjs';

const AREAS = [
  {
    id: 'app',
    cwd: 'app',
    matches: (p) =>
      p.startsWith('app/') && /\.(dart|arb|yaml)$/.test(p) && !GENERATED_DART.test(p) && !p.startsWith(L10N_GEN_DIR),
    steps: [['flutter analyze', 'flutter analyze']],
  },
  {
    id: 'functions',
    cwd: 'functions',
    matches: (p) => p.startsWith('functions/') && /\.(ts|mjs|json)$/.test(p) && !p.startsWith('functions/lib/'),
    steps: [
      ['typecheck', 'npm run --silent typecheck'],
      ['lint', 'npm run --silent lint'],
      ['testes do domínio', 'npm test --silent'],
    ],
  },
];

const MAX_CONSECUTIVE_BLOCKS = 4;
const CACHE_FILE = join(ROOT, VERIFY_CACHE);

const input = await readInput();
const changed = changedFiles();
if (!changed) process.exit(0); // fora de um repositório git

const cache = loadCache();
cache.fingerprints ??= {};
cache.results ??= {};
const failures = [];

for (const area of AREAS) {
  const files = changed.filter(area.matches).sort();
  if (files.length === 0) {
    delete cache.results[area.id]; // nada pendente nesta área
    continue;
  }

  const fingerprint = hashFiles(files);
  if (cache.fingerprints[area.id] === fingerprint) continue; // já verificado com este conteúdo

  let result = { ok: true, step: null, at: Date.now() };
  for (const [label, command] of area.steps) {
    const output = run(command, join(ROOT, area.cwd));
    if (output.ok) continue;
    if (isMissingCommand(output.output)) {
      result = { ok: null, step: `${label} (ferramenta ausente)`, at: Date.now() };
      break;
    }
    result = { ok: false, step: label, at: Date.now() };
    failures.push(`### ${area.id}: ${label} (\`cd ${area.cwd} && ${command}\`)\n${tail(output.output)}`);
    break; // o primeiro passo que falha já basta
  }
  // Grava a impressão digital também na falha: se o Claude parar sem mudar nada, não bloqueia de novo.
  cache.fingerprints[area.id] = fingerprint;
  cache.results[area.id] = result;
}

cache.blocks = failures.length === 0 ? 0 : (cache.blocks ?? 0) + 1;
saveCache(cache);

if (failures.length === 0) process.exit(0);
if (input.stop_hook_active && cache.blocks > MAX_CONSECUTIVE_BLOCKS) process.exit(0);

console.error(
  [
    'A verificação automática do projeto falhou nos arquivos alterados (hook .claude/hooks/verify.mjs).',
    'Corrija os problemas abaixo. Se não for possível ou não fizer parte da tarefa, explique ao usuário o que ficou pendente.',
    '',
    ...failures,
  ].join('\n'),
);
process.exit(2);

function hashFiles(files) {
  const hash = createHash('sha1');
  for (const file of files) {
    hash.update(file);
    const abs = join(ROOT, file);
    hash.update(existsSync(abs) ? readFileSync(abs) : '<removido>');
  }
  return hash.digest('hex');
}

function loadCache() {
  try {
    return JSON.parse(readFileSync(CACHE_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveCache(data) {
  try {
    mkdirSync(dirname(CACHE_FILE), { recursive: true });
    writeFileSync(CACHE_FILE, JSON.stringify(data, null, 2));
  } catch {
    // o cache é opcional
  }
}
