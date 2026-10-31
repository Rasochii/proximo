// A trava de ponta a ponta: commits de verdade, com o pre-commit real, num repositório temporário e com
// os mesmos eventos que o Claude Code envia. Nunca toca no estado de revisão do repositório real.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

const GATE = join(dirname(fileURLToPath(import.meta.url)), 'review-gate.mjs');
const CODE = 'functions/src/a.ts';

let repo;

const git = (cwd, ...args) =>
  spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, encoding: 'utf8' });

const runGate = (input) =>
  spawnSync(process.execPath, [GATE], {
    input: JSON.stringify(input),
    encoding: 'utf8',
    env: { ...process.env, CLAUDE_PROJECT_DIR: repo },
  });

/** Um revisor que começa, entrega o relatório pela ferramenta de encerramento e termina. */
function review(verdict, agentId, { agent = 'backend-reviewer', during } = {}) {
  runGate({ hook_event_name: 'SubagentStart', agent_type: agent, agent_id: agentId });
  during?.();
  const transcript = join(repo, `transcript-${agentId}.jsonl`);
  const message = { role: 'assistant', content: [{ type: 'tool_use', name: 'SubagentHandback', input: { message: verdict } }] };
  writeFileSync(transcript, JSON.stringify({ message }));
  runGate({ hook_event_name: 'SubagentStop', agent_type: agent, agent_id: agentId, agent_transcript_path: transcript });
}

const change = (text, file = CODE, root = repo) => appendFileSync(join(root, file), `${text}\n`);
const commitAll = (cwd = repo) => git(cwd, 'commit', '-am', 'x');
const approved = (id) => review('Tudo certo.\nVEREDITO: aprovado', id);

before(() => {
  repo = mkdtempSync(join(tmpdir(), 'proximo-trava-'));
  git(repo, 'init', '-q');
  writeFileSync(join(repo, '.gitignore'), 'transcript-*\n');
  mkdirSync(join(repo, 'functions/src'), { recursive: true });
  writeFileSync(join(repo, CODE), 'export {};\n');
  writeFileSync(join(repo, 'NOTAS.md'), 'notas\n');
  git(repo, 'add', '.');
  git(repo, 'commit', '-qm', 'base');

  // O mesmo .githooks/pre-commit do projeto, chamando a trava pelo caminho absoluto.
  const hooks = join(repo, '..', `${basename(repo)}-hooks`);
  mkdirSync(hooks);
  const script = `#!/bin/sh\nexec node "${GATE.replaceAll('\\', '/')}" --pre-commit\n`;
  writeFileSync(join(hooks, 'pre-commit'), script, { mode: 0o755 });
  git(repo, 'config', 'core.hooksPath', hooks.replaceAll('\\', '/'));
});

after(() => {
  rmSync(repo, { recursive: true, force: true });
  rmSync(`${repo}-hooks`, { recursive: true, force: true });
  rmSync(`${repo}-wt`, { recursive: true, force: true });
});

describe('trava de commit, de ponta a ponta', () => {
  it('sem código no commit, passa, mesmo com código alterado fora dele', () => {
    change('// 1');
    change('mais notas', 'NOTAS.md');
    git(repo, 'add', 'NOTAS.md');
    assert.equal(git(repo, 'commit', '-m', 'notas').status, 0);
  });

  it('código sem revisão barra e diz quem falta', () => {
    const result = commitAll();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /backend-reviewer/);
    assert.doesNotMatch(result.stderr, /Error:/);
  });

  it('revisor que pede correção mantém barrado', () => {
    review('Achado Alto.\nVEREDITO: corrigir', 'r1');
    assert.match(commitAll().stderr, /o revisor pediu correção/);
  });

  it('relatório sem veredito não aprova', () => {
    review('Parece bom.', 'r2');
    assert.match(commitAll().stderr, /não deu veredito/);
  });

  it('agente que não é revisor não aprova nada', () => {
    review('VEREDITO: aprovado', 'r3', { agent: 'Explore' });
    assert.notEqual(commitAll().status, 0);
  });

  it('o revisor da área aprovando, o commit passa', () => {
    approved('r4');
    assert.equal(commitAll().status, 0);
  });

  it('alterar depois da aprovação barra de novo', () => {
    change('// 2');
    approved('r5');
    change('// 3');
    assert.match(commitAll().stderr, /não é o conteúdo que foi revisado/);
  });

  it('alteração durante a revisão não é aprovada', () => {
    review('VEREDITO: aprovado', 'r6', { during: () => change('// 4') });
    assert.notEqual(commitAll().status, 0);
  });

  it('o commit grava o stage: versão antiga em stage barra, mesmo com o arquivo aprovado', () => {
    git(repo, 'add', CODE);
    change('// 5');
    approved('r7');
    assert.notEqual(git(repo, 'commit', '-m', 'x').status, 0);
    git(repo, 'add', CODE);
    assert.equal(git(repo, 'commit', '-m', 'x').status, 0);
  });

  it('caminho com acento: alterar depois da aprovação barra', () => {
    const file = 'functions/src/configuração.ts';
    writeFileSync(join(repo, file), 'export {};\n');
    git(repo, 'add', file);
    approved('r8');
    change('// mudou', file);
    git(repo, 'add', file);
    assert.notEqual(git(repo, 'commit', '-m', 'x').status, 0);
    git(repo, 'reset', '-q', '--hard');
  });

  it('arquivo movido para fora da área revisada conta como mudança', () => {
    git(repo, 'mv', CODE, 'fora.ts');
    assert.match(git(repo, 'commit', '-m', 'x').stderr, /backend-reviewer/);
    git(repo, 'reset', '-q', '--hard');
  });

  it('commit em outra worktree é julgado pelo estado dela', () => {
    const other = `${repo}-wt`;
    git(repo, 'worktree', 'add', '-q', other);
    change('// só na worktree', CODE, other);
    assert.notEqual(commitAll(other).status, 0);
    git(repo, 'worktree', 'remove', '--force', other);
  });

  it('num merge, o que veio do outro branch não pede revisão de novo', () => {
    git(repo, 'checkout', '-q', '-b', 'lado');
    change('// lado', 'NOTAS.md');
    git(repo, 'commit', '-qam', 'lado', '--no-verify');
    change('// código do lado');
    git(repo, 'commit', '-qam', 'código', '--no-verify');
    git(repo, 'checkout', '-q', '-');
    change('// principal', 'NOTAS.md');
    git(repo, 'commit', '-qam', 'principal');

    assert.notEqual(git(repo, 'merge', '--no-edit', 'lado').status, 0); // conflito em NOTAS.md
    writeFileSync(join(repo, 'NOTAS.md'), 'resolvido\n');
    git(repo, 'add', 'NOTAS.md');
    assert.equal(git(repo, 'commit', '--no-edit').status, 0);
  });

  it('num merge, arquivo apagado pelo outro branch não pede revisão', () => {
    writeFileSync(join(repo, 'functions/src/b.ts'), 'export {};\n');
    git(repo, 'add', '.');
    review('VEREDITO: aprovado', 'r10');
    git(repo, 'commit', '-qm', 'b');
    git(repo, 'checkout', '-q', '-b', 'apaga');
    git(repo, 'rm', '-q', 'functions/src/b.ts');
    change('// apaga', 'NOTAS.md');
    git(repo, 'add', '.');
    git(repo, 'commit', '-qm', 'apaga', '--no-verify');
    git(repo, 'checkout', '-q', '-');
    change('// outro', 'NOTAS.md');
    git(repo, 'commit', '-qam', 'outro');

    assert.notEqual(git(repo, 'merge', '--no-edit', 'apaga').status, 0);
    writeFileSync(join(repo, 'NOTAS.md'), 'resolvido 3\n');
    git(repo, 'add', 'NOTAS.md');
    assert.equal(git(repo, 'commit', '--no-edit').status, 0);
  });

  it('num merge, editar outro código durante o merge continua pedindo revisão', () => {
    git(repo, 'checkout', '-q', '-b', 'lado2');
    change('// lado2', 'NOTAS.md');
    git(repo, 'commit', '-qam', 'lado2');
    git(repo, 'checkout', '-q', '-');
    change('// principal2', 'NOTAS.md');
    git(repo, 'commit', '-qam', 'principal2');

    git(repo, 'merge', '--no-edit', 'lado2');
    writeFileSync(join(repo, 'NOTAS.md'), 'resolvido 2\n');
    change('// escondido no merge');
    git(repo, 'add', '.');
    assert.match(git(repo, 'commit', '--no-edit').stderr, /backend-reviewer/);

    git(repo, 'merge', '--abort');
  });

  it('um revisor retomado, sem novo início, ainda registra o veredito', () => {
    change('// 7');
    review('Achado Alto.\nVEREDITO: corrigir', 'r9');
    const transcript = join(repo, 'transcript-r9.jsonl');
    const message = { role: 'assistant', content: [{ type: 'text', text: 'Revi a evidência.\nVEREDITO: aprovado' }] };
    writeFileSync(transcript, JSON.stringify({ message }));
    runGate({ hook_event_name: 'SubagentStop', agent_type: 'backend-reviewer', agent_id: 'r9', agent_transcript_path: transcript });
    assert.equal(commitAll().status, 0);
  });

  it('uma pessoa pode pular a trava no terminal dela', () => {
    change('// 6');
    assert.equal(git(repo, 'commit', '-am', 'x', '--no-verify').status, 0);
  });
});

describe('o script da trava', () => {
  it('argumento desconhecido barra, em vez de deixar o commit passar', () => {
    // É o que aconteceria com o .githooks/pre-commit em CRLF: o argumento chegaria com um \r no fim.
    const result = spawnSync(process.execPath, [GATE, '--pre-commit\r'], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
  });

  it('o pre-commit do projeto sai sempre com fim de linha LF', () => {
    const root = join(dirname(GATE), '..', '..');
    const attributes = git(root, 'check-attr', 'eol', '--', '.githooks/pre-commit').stdout;
    assert.match(attributes, /eol: lf/);
    assert.doesNotMatch(readFileSync(join(root, '.githooks/pre-commit'), 'utf8'), /\r/);
  });
});

describe('o Claude não desliga a trava', () => {
  const tryCommand = (command) =>
    runGate({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command } }).status;

  it('barra os atalhos', () => {
    assert.equal(tryCommand('git commit -am x --no-verify'), 2);
    assert.equal(tryCommand('git commit -nm x'), 2);
    assert.equal(tryCommand('git -c core.hooksPath=/dev/null commit -m x'), 2);
  });

  it('o resto passa', () => {
    assert.equal(tryCommand('git commit -m x'), 0);
    assert.equal(tryCommand('git status'), 0);
  });
});
