import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  blockMessage,
  inReviewScope,
  isBypassCommand,
  parseVerdict,
  pendingReviews,
  recordReview,
  reportFromTranscript,
  scopeFor,
} from './review-rules.mjs';

describe('isBypassCommand', () => {
  it('reconhece o que desliga a trava', () => {
    for (const command of [
      'git commit -m x --no-verify',
      'git commit -n -m x',
      'git commit -nm x',
      'git -c core.hooksPath=/dev/null commit -m x',
      'git config --unset core.hooksPath',
      'git config core.hookspath /dev/null',
      'git -c CORE.HOOKSPATH=x commit -m y',
      'git commit --no-ver -m x',
      'git add . && git commit -nm x && git push',
      'git commit -m "fix: A & B" --no-verify',
      'git commit -am x -n; if ($?) { git push }',
      'git commit -nm"wip"',
      'git -c core.hooksPath=/dev/null commit -m "usa --get"',
      'git commit \\\n  --no-verify -m x',
    ]) {
      assert.equal(isBypassCommand(command), true, command);
    }
  });

  it('deixa o resto passar', () => {
    for (const command of [
      'git commit -m x',
      'git commit -am x',
      'git log -n 3',
      'git log --grep=commit -n 5',
      'git config --get core.hooksPath',
      'grep -n core.hooksPath docs/adr/0008.md',
      'git status',
      '',
      undefined,
    ]) {
      assert.equal(isBypassCommand(command), false, String(command));
    }
  });
});

describe('parseVerdict', () => {
  it('lê a última linha de veredito, com ou sem negrito', () => {
    assert.equal(parseVerdict('relatório\n\nVEREDITO: aprovado'), 'aprovado');
    assert.equal(parseVerdict('**VEREDITO: corrigir**'), 'corrigir');
  });

  it('vale a última linha, se o relatório citar o formato antes', () => {
    assert.equal(parseVerdict('VEREDITO: corrigir\n...\nVEREDITO: aprovado\n\n'), 'aprovado');
  });

  it('veredito que não é a última linha não vale: o relatório pode ter continuado', () => {
    assert.equal(parseVerdict('Rodada anterior\nVEREDITO: aprovado\n\nAgora achei um Alto em x.ts'), null);
  });

  it('aprovação com ressalva não é aprovação', () => {
    assert.equal(parseVerdict('VEREDITO: aprovado com ressalvas'), null);
    assert.equal(parseVerdict('VEREDITO: aprovado-condicional'), null);
  });

  it('aceita a linha formatada', () => {
    assert.equal(parseVerdict('## VEREDITO: corrigir'), 'corrigir');
    assert.equal(parseVerdict('**VEREDITO:** aprovado'), 'aprovado');
    assert.equal(parseVerdict('```\nVEREDITO: aprovado\n```'), 'aprovado');
  });

  it('sem linha de veredito, não presume aprovação', () => {
    assert.equal(parseVerdict('pode commitar'), null);
    assert.equal(parseVerdict(null), null);
  });
});

describe('reportFromTranscript', () => {
  const line = (role, content) => JSON.stringify({ message: { role, content } });

  it('lê a entrega pela ferramenta de encerramento (formato real do agente em segundo plano)', () => {
    const jsonl = [
      line('assistant', [{ type: 'thinking', thinking: '' }]),
      line('assistant', [{ type: 'tool_use', name: 'SubagentHandback', input: { message: 'Fim.\nVEREDITO: aprovado' } }]),
      JSON.stringify({ type: 'attachment', attachment: { hookName: 'SubagentStop' } }),
    ].join('\n');
    assert.equal(parseVerdict(reportFromTranscript(jsonl)), 'aprovado');
  });

  it('revisor cortado depois de um veredito antigo não tem relatório', () => {
    const jsonl = [
      line('assistant', [{ type: 'text', text: 'VEREDITO: aprovado' }]),
      line('assistant', [{ type: 'tool_use', name: 'Bash', input: { command: 'grep x' } }]),
    ].join('\n');
    assert.equal(reportFromTranscript(jsonl), null);
  });

  it('lê texto comum', () => {
    assert.equal(reportFromTranscript(line('assistant', [{ type: 'text', text: 'relatório' }])), 'relatório');
  });

  it('não confunde uma mensagem enviada a outro agente com o relatório', () => {
    const jsonl = line('assistant', [{ type: 'tool_use', name: 'SendMessage', input: { message: 'VEREDITO: aprovado' } }]);
    assert.equal(reportFromTranscript(jsonl), null);
  });

  it('ignora linha quebrada', () => {
    assert.equal(reportFromTranscript(`${line('assistant', [{ type: 'text', text: 'ok' }])}\n{quebrada`), 'ok');
  });
});

describe('scopeFor', () => {
  const blobs = {
    'app/lib/features/x/presentation/x_controller.dart': 'a',
    'app/lib/features/x/presentation/x_view.dart': 'b',
    'app/lib/l10n/app_pt.arb': 'c',
    'app/test/x_test.dart': 'd',
    'functions/src/domain/commands.ts': 'e',
    'functions/scripts/seed-emulator.ts': 'f',
    'firestore.rules': 'g',
    'README.md': 'h',
    'estudo/x.md': 'i',
  };

  it('dá a cada revisor a sua área', () => {
    assert.deepEqual(Object.keys(scopeFor('backend-reviewer', blobs)), [
      'functions/src/domain/commands.ts',
      'functions/scripts/seed-emulator.ts',
      'firestore.rules',
    ]);
    assert.deepEqual(Object.keys(scopeFor('ux-a11y-reviewer', blobs)), [
      'app/lib/features/x/presentation/x_view.dart',
      'app/lib/l10n/app_pt.arb',
    ]);
    assert.equal(Object.keys(scopeFor('flutter-reviewer', blobs)).length, 4);
  });

  it('agente que não é revisor não tem área', () => {
    assert.deepEqual(scopeFor('Explore', blobs), {});
  });

  it('as configurações que garantem as invariantes entram na conta', () => {
    for (const path of [
      'functions/eslint.config.mjs',
      'functions/tsconfig.build.json',
      'functions/package-lock.json',
      'firebase.json',
      'app/analysis_options.yaml',
      'app/pubspec.lock',
      'app/android/app/src/main/AndroidManifest.xml',
      'app/ios/Runner/Info.plist',
      'app/web/index.html',
    ]) {
      assert.equal(inReviewScope(path), true, path);
    }
  });
});

describe('pendingReviews', () => {
  const file = 'functions/src/domain/commands.ts';

  it('documentação não precisa de revisor', () => {
    assert.deepEqual(pendingReviews({ 'README.md': 'x' }, {}), []);
  });

  it('código sem revisão barra', () => {
    assert.deepEqual(pendingReviews({ [file]: 'x' }, {}), [
      { agent: 'backend-reviewer', path: file, reason: 'ainda não foi revisado' },
    ]);
  });

  it('aprovado para o conteúdo atual libera', () => {
    const records = { 'backend-reviewer': { [file]: { hash: 'x', verdict: 'aprovado' } } };
    assert.deepEqual(pendingReviews({ [file]: 'x' }, records), []);
  });

  it('conteúdo diferente do aprovado barra', () => {
    const records = { 'backend-reviewer': { [file]: { hash: 'antigo', verdict: 'aprovado' } } };
    assert.equal(pendingReviews({ [file]: 'novo' }, records)[0].reason, 'não é o conteúdo que foi revisado');
  });

  it('o revisor pedir correção barra, mesmo com o conteúdo igual', () => {
    const records = { 'backend-reviewer': { [file]: { hash: 'x', verdict: 'corrigir' } } };
    assert.equal(pendingReviews({ [file]: 'x' }, records)[0].reason, 'o revisor pediu correção');
  });

  it('revisão sem veredito, ou com qualquer outro valor, não aprova', () => {
    for (const verdict of ['sem-veredito', 'liberado', undefined]) {
      const records = { 'backend-reviewer': { [file]: { hash: 'x', verdict } } };
      assert.equal(pendingReviews({ [file]: 'x' }, records)[0].reason, 'o revisor não deu veredito');
    }
  });

  it('commits parciais: só conta o que vai no commit', () => {
    const records = { 'backend-reviewer': { 'firestore.rules': { hash: 'y', verdict: 'aprovado' } } };
    assert.deepEqual(pendingReviews({ 'firestore.rules': 'y' }, records), []);
  });

  it('tela alterada exige os dois revisores do app', () => {
    const agents = pendingReviews({ 'app/lib/x/presentation/y_view.dart': 'z' }, {}).map((p) => p.agent);
    assert.deepEqual(agents, ['flutter-reviewer', 'ux-a11y-reviewer']);
  });
});

describe('recordReview', () => {
  it('registra o veredito do que o revisor viu', () => {
    assert.deepEqual(recordReview({ a: '1' }, { a: '1' }, 'aprovado'), { a: { hash: '1', verdict: 'aprovado' } });
  });

  it('o que mudou durante a revisão não conta', () => {
    assert.deepEqual(recordReview({ a: '1', b: '2' }, { a: '9', b: '2' }, 'aprovado'), {
      b: { hash: '2', verdict: 'aprovado' },
    });
  });

  it('arquivo criado durante a revisão não conta', () => {
    assert.deepEqual(recordReview({}, { a: '1' }, 'aprovado'), {});
  });

  it('sem veredito fica marcado como tal', () => {
    assert.equal(recordReview({ a: '1' }, { a: '1' }, null).a.verdict, 'sem-veredito');
  });
});

describe('blockMessage', () => {
  it('diz quem falta e por quê', () => {
    const message = blockMessage([{ agent: 'backend-reviewer', path: 'firestore.rules', reason: 'ainda não foi revisado' }]);
    assert.match(message, /backend-reviewer/);
    assert.match(message, /firestore\.rules: ainda não foi revisado/);
  });
});

