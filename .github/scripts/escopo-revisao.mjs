// Lê nomes de arquivo pela entrada padrão e diz se o PR tem o que revisar, no formato do $GITHUB_OUTPUT.
// A lista é uma só: a mesma da trava de commit (REVIEWERS em .claude/hooks/review-rules.mjs).
import { readFileSync } from 'node:fs';

import { inReviewScope } from '../../.claude/hooks/review-rules.mjs';

const files = readFileSync(0, 'utf8').split(/\r?\n/).filter(Boolean);
console.log(`relevante=${files.some(inReviewScope)}`);
