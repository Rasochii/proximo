// SessionStart (startup, resume, clear, compact): injeta no contexto do Claude um retrato rápido do repositório,
// para cada sessão começar situada sem precisar perguntar ou explorar.
// Tudo que este script imprime no stdout (com exit 0) vira contexto para o Claude.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { changedFiles, countByArea, currentPhase, git, readInput, ROOT, VERIFY_CACHE } from './lib.mjs';

const input = await readInput();
const lines = ['## Contexto do repositório (gerado pelo hook SessionStart)'];

// Git: branch, sincronia com o remoto, mudanças e últimos commits.
const branch = git('branch', '--show-current').stdout.trim() || '(HEAD destacado)';
const sync = git('rev-list', '--left-right', '--count', '@{upstream}...HEAD');
const syncText = sync.ok
  ? (() => {
      const [behind, ahead] = sync.stdout.trim().split(/\s+/).map(Number);
      return ahead || behind ? ` (${ahead} à frente, ${behind} atrás do remoto)` : ' (em dia com o remoto)';
    })()
  : ' (sem upstream)';
lines.push(`- Branch: \`${branch}\`${syncText}`);
if (branch === 'main' || branch === 'master') {
  lines.push('  - Atenção: você está na branch principal. Para implementar algo, sugira criar `feat/*` ou `fix/*` antes.');
}

const files = changedFiles();
if (files) {
  const counts = countByArea(files);
  const total = counts.app + counts.functions + counts.outros;
  if (total === 0) {
    lines.push('- Working tree limpa.');
  } else {
    lines.push(`- Mudanças não commitadas: ${total} (app ${counts.app}, functions ${counts.functions}, outros ${counts.outros})`);
    const shown = files.filter((f) => !f.startsWith('.claude/.cache/')).slice(0, 15);
    for (const file of shown) lines.push(`  - ${file}`);
    if (files.length > shown.length) lines.push(`  - … e mais ${files.length - shown.length}`);
  }
}

const log = git('log', '-5', '--pretty=format:%h %s (%cr)');
if (log.ok && log.stdout.trim()) {
  lines.push('- Últimos commits:');
  for (const entry of log.stdout.trim().split(/\r?\n/)) lines.push(`  - ${entry}`);
}

// Fase do roadmap segundo o README.
try {
  const phase = currentPhase(readFileSync(join(ROOT, 'README.md'), 'utf8'));
  if (phase) lines.push(`- Fase atual (README): **${phase.id} — ${phase.title}** · ${phase.status}. Plano em docs/PLANO_DE_ACAO.md.`);
} catch {
  // sem README
}

// Última verificação do hook Stop.
try {
  const cache = JSON.parse(readFileSync(join(ROOT, VERIFY_CACHE), 'utf8'));
  const failed = Object.entries(cache.results ?? {}).filter(([, r]) => r.ok === false);
  for (const [area, result] of failed) {
    lines.push(`- ⚠️ A última verificação de **${area}** falhou em "${result.step}". Confirme se isso já foi resolvido antes de seguir.`);
  }
} catch {
  // sem cache ainda
}

// Código gerado ausente (comum após clone ou troca de branch).
const pending = [];
if (existsSync(join(ROOT, 'app/lib/l10n')) && !existsSync(join(ROOT, 'app/lib/l10n/gen/app_localizations.dart'))) {
  pending.push('strings não geradas → `cd app && flutter gen-l10n`');
}
if (missingCodegen(join(ROOT, 'app/lib'))) {
  pending.push('arquivos *.g.dart/*.freezed.dart faltando → `cd app && dart run build_runner build --delete-conflicting-outputs`');
}
if (existsSync(join(ROOT, 'functions/package.json')) && !existsSync(join(ROOT, 'functions/node_modules'))) {
  pending.push('dependências do backend não instaladas → `cd functions && npm install`');
}
if (pending.length > 0) {
  lines.push('- Pendências de ambiente (rode antes de analisar ou testar):');
  for (const item of pending) lines.push(`  - ${item}`);
}

if (input.source === 'compact') {
  lines.push('- A conversa acabou de ser compactada: releia os arquivos que for editar em vez de confiar no resumo.');
}

console.log(lines.join('\n'));

/** true se algum .dart declara `part 'x.g.dart'`/`x.freezed.dart'` e o arquivo gerado não existe. */
function missingCodegen(dir) {
  if (!existsSync(dir)) return false;
  for (const entry of readdirSync(dir, { withFileTypes: true, recursive: true })) {
    if (!entry.isFile() || !entry.name.endsWith('.dart') || /\.(g|freezed)\.dart$/.test(entry.name)) continue;
    const folder = entry.parentPath ?? entry.path;
    const source = readFileSync(join(folder, entry.name), 'utf8');
    for (const match of source.matchAll(/^part\s+['"]([^'"]+\.(?:g|freezed)\.dart)['"];/gm)) {
      if (!existsSync(join(folder, match[1]))) return true;
    }
  }
  return false;
}
