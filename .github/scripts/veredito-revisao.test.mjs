import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';

import { BOT, decide, hasBlockingInline, isContested, verdictFor } from './veredito-revisao.mjs';

const SHA = 'abc1234def5678';
const OWNER = 'dono';
const marker = (bloqueante, sha = SHA) => `Revisão.\n\n<!-- veredito-revisao sha=${sha} bloqueante=${bloqueante} -->\n`;
const fromBot = (body) => ({ author: BOT, body });
const base = { scope: 'success', relevant: 'true', comments: [], inline: [], sha: SHA, owner: OWNER };

describe('escopo-revisao', () => {
  const script = fileURLToPath(new URL('./escopo-revisao.mjs', import.meta.url));
  const scope = (input) => spawnSync(process.execPath, [script], { input, encoding: 'utf8' }).stdout.trim();

  it('diz se há o que revisar, no formato do GITHUB_OUTPUT', () => {
    assert.equal(scope('README.md\nfirestore.rules\n'), 'relevante=true');
    assert.equal(scope('README.md\ndocs/adr/1.md\n'), 'relevante=false');
    assert.equal(scope(''), 'relevante=false');
  });
});

describe('verdictFor', () => {
  it('lê o veredito do commit atual', () => {
    assert.equal(verdictFor([fromBot(marker('nao'))], SHA), 'nao');
  });

  it('veredito de outro commit não vale', () => {
    assert.equal(verdictFor([fromBot(marker('nao', 'outro'))], SHA), null);
  });

  it('ignora marcador escrito por outra pessoa', () => {
    assert.equal(verdictFor([{ author: 'visitante', body: marker('nao') }], SHA), null);
  });

  it('só vale na última linha: citar o marcador no meio do texto não conta', () => {
    assert.equal(verdictFor([fromBot(`${marker('nao')}\nE achei um problema.`)], SHA), null);
  });

  it('marcador sem preencher não vale', () => {
    assert.equal(verdictFor([fromBot(marker('X'))], SHA), null);
  });

  it('com dois vereditos para o mesmo commit, o bloqueante ganha', () => {
    assert.equal(verdictFor([fromBot(marker('sim')), fromBot(marker('nao'))], SHA), 'sim');
  });
});

describe('hasBlockingInline', () => {
  const inline = (body, commit = SHA, author = BOT) => ({ author, body, commit });

  it('achado Crítico ou Alto neste commit bloqueia', () => {
    assert.equal(hasBlockingInline([inline('[Alto] risco')], SHA), true);
    assert.equal(hasBlockingInline([inline('[Crítico] risco')], SHA), true);
    assert.equal(hasBlockingInline([inline('**[Alto]** risco')], SHA), true);
    assert.equal(hasBlockingInline([inline('[alto] risco')], SHA), true);
  });

  it('achado menor, de outro commit ou de outra pessoa, não bloqueia', () => {
    assert.equal(hasBlockingInline([inline('[Médio] risco')], SHA), false);
    assert.equal(hasBlockingInline([inline('[Alto] risco', 'outro')], SHA), false);
    assert.equal(hasBlockingInline([inline('[Alto] risco', SHA, 'visitante')], SHA), false);
  });
});

describe('isContested', () => {
  const contest = (body, author = OWNER) => [{ author, body }];

  it('o dono contesta um commit pelo hash, completo ou curto', () => {
    assert.equal(isContested(contest(`/contestar ${SHA}`), SHA, OWNER), true);
    assert.equal(isContested(contest('/contestar abc1234'), SHA, OWNER), true);
  });

  it('só o dono contesta', () => {
    assert.equal(isContested(contest('/contestar abc1234', 'outra-conta'), SHA, OWNER), false);
  });

  it('a contestação não passa para o commit seguinte', () => {
    assert.equal(isContested(contest('/contestar 0000000'), SHA, OWNER), false);
  });

  it('hash curto demais não vale', () => {
    assert.equal(isContested(contest('/contestar abc'), SHA, OWNER), false);
  });
});

describe('decide', () => {
  it('PR sem código revisado passa', () => {
    assert.equal(decide({ ...base, relevant: 'false' }).ok, true);
  });

  it('sem achado bloqueante passa', () => {
    assert.equal(decide({ ...base, comments: [fromBot(marker('nao'))] }).ok, true);
  });

  it('achado Crítico ou Alto reprova', () => {
    assert.equal(decide({ ...base, comments: [fromBot(marker('sim'))] }).ok, false);
  });

  it('comentário inline Alto reprova mesmo com o marcador dizendo que não', () => {
    const inline = [{ author: BOT, body: '[Alto] risco', commit: SHA }];
    assert.equal(decide({ ...base, comments: [fromBot(marker('nao'))], inline }).ok, false);
  });

  it('revisão sem veredito reprova', () => {
    assert.equal(decide(base).ok, false);
  });

  it('sem a resposta do escopo, reprova em vez de presumir que não há o que revisar', () => {
    assert.equal(decide({ ...base, relevant: '' }).ok, false);
  });

  it('se o passo de escopo falhou, reprova em vez de presumir que não há o que revisar', () => {
    assert.equal(decide({ ...base, scope: 'failure', relevant: '' }).ok, false);
  });

  it('a contestação do dono vale mais que o veredito, só para aquele commit', () => {
    const comments = [fromBot(marker('sim')), { author: OWNER, body: '/contestar abc1234' }];
    assert.equal(decide({ ...base, comments }).ok, true);
    assert.equal(decide({ ...base, comments, sha: 'def9999000' }).ok, false);
  });
});
