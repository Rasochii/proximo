/**
 * Executa os testes com `tsx --test`, listando os arquivos aqui mesmo.
 *
 * Por quê: o cmd/PowerShell do Windows não expande `test/*.test.ts`, e o suporte a glob do
 * próprio `node --test` só existe a partir do Node 21. Listar os arquivos funciona em qualquer SO.
 *
 * Uso: node scripts/run-tests.mjs <pasta> [flags extras do node --test]
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const [dir = 'test', ...extraArgs] = process.argv.slice(2);
if (!existsSync(dir)) {
  console.error(`Pasta de testes "${dir}" não encontrada.`);
  process.exit(1);
}

const files = readdirSync(dir)
  .filter((name) => name.endsWith('.test.ts'))
  .sort()
  .map((name) => join(dir, name));

if (files.length === 0) {
  console.error(`Nenhum arquivo *.test.ts encontrado em "${dir}".`);
  process.exit(1);
}

const tsxCli = createRequire(import.meta.url).resolve('tsx/cli');
const result = spawnSync(process.execPath, [tsxCli, '--test', ...extraArgs, ...files], { stdio: 'inherit' });
process.exit(result.status ?? 1);
