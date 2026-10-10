// @ts-check
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['lib/**', 'node_modules/**'] },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: { project: './tsconfig.test.json', tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@typescript-eslint/restrict-template-expressions': ['error', { allowNumber: true }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['firebase-admin*', 'firebase-functions*', '../firebase/*'],
              message: 'O domínio deve permanecer puro (ADR 0004/0005).',
            },
          ],
        },
      ],
    },
  },
  {
    files: ['src/firebase/**', 'src/index.ts', 'scripts/**', 'test-emulator/**'],
    rules: { 'no-restricted-imports': 'off' },
  },
);
