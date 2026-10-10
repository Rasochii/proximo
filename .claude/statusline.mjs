// Status line do Claude Code para o Próximo!.
// Exemplo: Opus · feat/console · F2 🚧 · ✎ app 3 · fn 1 · ✓ verificado · ctx 23% · $0.42
// Recebe o JSON da sessão pelo stdin e imprime uma linha. Precisa ser rápido: sem rede, só git local.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { changedFiles, countByArea, currentPhase, git, readInput, ROOT, VERIFY_CACHE } from './hooks/lib.mjs';

const color = (code) => (text) => `\x1b[${code}m${text}\x1b[0m`;
const dim = color('2');
const green = color('32');
const yellow = color('33');
const red = color('31');
const cyan = color('36');

const session = await readInput();
const parts = [];

if (session.model?.display_name) parts.push(cyan(session.model.display_name));

const branch = git('branch', '--show-current').stdout.trim();
if (branch) parts.push(branch === 'main' ? yellow(`${branch} ⚠`) : branch);

try {
  const phase = currentPhase(readFileSync(join(ROOT, 'README.md'), 'utf8'));
  if (phase) parts.push(`${phase.id} ${phase.status.includes('🚧') ? '🚧' : '⏳'}`);
} catch {
  // sem README
}

const files = changedFiles();
if (files) {
  const counts = countByArea(files);
  const changes = [
    counts.app && `app ${counts.app}`,
    counts.functions && `fn ${counts.functions}`,
    counts.outros && `outros ${counts.outros}`,
  ].filter(Boolean);
  parts.push(changes.length > 0 ? `✎ ${changes.join(' · ')}` : dim('limpo'));
}

try {
  const cache = JSON.parse(readFileSync(join(ROOT, VERIFY_CACHE), 'utf8'));
  const results = Object.entries(cache.results ?? {});
  const failed = results.filter(([, r]) => r.ok === false).map(([area]) => area);
  if (failed.length > 0) parts.push(red(`✗ ${failed.join(', ')}`));
  else if (results.some(([, r]) => r.ok === true)) parts.push(green('✓ verificado'));
} catch {
  // ainda não houve verificação
}

const used = session.context_window?.used_percentage;
if (typeof used === 'number') {
  const text = `ctx ${Math.round(used)}%`;
  parts.push(used >= 80 ? red(text) : used >= 60 ? yellow(text) : dim(text));
}

const cost = session.cost?.total_cost_usd;
if (typeof cost === 'number' && cost > 0) parts.push(dim(`$${cost.toFixed(2)}`));

console.log(parts.join(dim(' · ')));
