// PostToolUse (Edit|Write|MultiEdit): formata Dart, regenera l10n e lembra do codegen.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { GENERATED_DART, isMissingCommand, L10N_GEN_DIR, readInput, ROOT, run, tail, toRepoPath } from './lib.mjs';

const input = await readInput();
const rel = toRepoPath(input.tool_input?.file_path);
if (!rel || !rel.startsWith('app/')) process.exit(0);

const appDir = join(ROOT, 'app');
const appRel = rel.slice('app/'.length);
const notes = [];

function fail(message) {
  console.error(message);
  process.exit(2); // PostToolUse: o arquivo já foi salvo; o stderr chega ao Claude para corrigir.
}

if (rel.endsWith('.dart') && !GENERATED_DART.test(rel) && !rel.startsWith(L10N_GEN_DIR)) {
  // Rodar dentro de app/ faz o dart format respeitar o page_width do analysis_options.yaml.
  const result = run(`dart format "${appRel}"`, appDir);
  if (!result.ok && !isMissingCommand(result.output)) {
    fail(`dart format falhou em ${rel} (provável erro de sintaxe):\n${tail(result.output, 30)}`);
  }

  let source = '';
  try {
    source = readFileSync(join(ROOT, rel), 'utf8');
  } catch {
    // arquivo removido entre a edição e o hook
  }
  if (/^part\s+['"][^'"]+\.(g|freezed)\.dart['"];/m.test(source)) {
    notes.push(
      `${rel} usa code generation. Antes de analisar ou testar, rode: cd app && dart run build_runner build --delete-conflicting-outputs`,
    );
  }
}

if (/^app\/lib\/l10n\/[^/]+\.arb$/.test(rel)) {
  const result = run('flutter gen-l10n', appDir);
  if (!result.ok && !isMissingCommand(result.output)) {
    fail(`flutter gen-l10n falhou depois de editar ${rel}:\n${tail(result.output, 30)}`);
  }
}

if (notes.length > 0) {
  console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: notes.join('\n') } }));
}
