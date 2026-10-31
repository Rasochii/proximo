// PreToolUse (Read|Edit|Write|MultiEdit): bloqueia leitura de segredos e edição de arquivos gerados.
// Saída com código 2 = ação bloqueada; a mensagem do stderr volta para o Claude.
import { GENERATED_DART, L10N_GEN_DIR, readInput, toRepoPath } from './lib.mjs';

const input = await readInput();
const tool = input.tool_name ?? '';
const rel = toRepoPath(input.tool_input?.file_path);
if (!rel) process.exit(0);

const name = rel.split('/').pop() ?? '';
const parts = rel.split('/');
const isWrite = tool !== 'Read';

function secretReason() {
  if (/^\.env(\..+)?$/.test(name) && name !== '.env.example') {
    return `${rel} pode conter segredos/configuração de ambiente. Peça ao usuário o valor necessário ou use .env.example.`;
  }
  if (/\.json$/.test(name) && /(service-?account|firebase-adminsdk)/i.test(name)) {
    return `${rel} parece ser uma chave de service account. Nunca leia nem versione esse arquivo.`;
  }
  if (/\.(jks|keystore|p12|p8|pem|mobileprovision)$/i.test(name) || name === 'key.properties') {
    return `${rel} é credencial de assinatura/certificado.`;
  }
  return null;
}

function writeReason() {
  if (parts[0] === '.git') return `${rel} é estado interno do git (inclui a trava de revisão).`;
  if (GENERATED_DART.test(name)) {
    return `${rel} é gerado pelo build_runner. Edite o arquivo-fonte e rode: cd app && dart run build_runner build --delete-conflicting-outputs`;
  }
  if (rel.startsWith(L10N_GEN_DIR)) {
    return `${rel} é gerado pelo gen-l10n. Edite app/lib/l10n/app_pt.arb (o hook regenera automaticamente).`;
  }
  if (rel.startsWith('functions/lib/')) return `${rel} é saída do tsc. Edite functions/src/.`;
  if (name === 'pubspec.lock' || name === 'package-lock.json') {
    return `${name} é gerenciado pelas ferramentas. Use flutter pub get / npm install (dependência nova exige justificativa).`;
  }
  if (parts.includes('node_modules') || parts.includes('.dart_tool') || rel.startsWith('app/build/') || parts.includes('Pods')) {
    return `${rel} é dependência/artefato de build.`;
  }
  return null;
}

const reason = secretReason() ?? (isWrite ? writeReason() : null);
if (reason) {
  console.error(`Bloqueado pelo hook do projeto (.claude/hooks/guard.mjs): ${reason}`);
  process.exit(2);
}
