// @ts-check
// Security overlay: used as a second ESLint pass when a project has its own eslint config
// but does not include eslint-plugin-security. Covers only the JS/TS common security rules
// from the baseline config (spec §6.4). Does NOT re-run core js.configs.recommended rules;
// the project's own config already covers those.
import { defineConfig } from 'eslint/config';
import security from 'eslint-plugin-security';
import regexp from 'eslint-plugin-regexp';
import noUnsanitized from 'eslint-plugin-no-unsanitized';

export default defineConfig(
  { ignores: ['**/dist/**', '**/build/**', '**/coverage/**', '**/*.min.js', '**/vendor/**'] },

  {
    files: ['**/*.{js,mjs,cjs,jsx,ts,mts,cts,tsx}'],
    plugins: { security, regexp, 'no-unsanitized': noUnsanitized },
    rules: {
      'no-eval': 'error',
      'no-new-func': 'error',
      'no-script-url': 'error',
      'security/detect-bidi-characters': 'error',
      'security/detect-buffer-noassert': 'error',
      'security/detect-child-process': 'error',
      'security/detect-eval-with-expression': 'error',
      'security/detect-new-buffer': 'error',
      'security/detect-non-literal-fs-filename': 'warn',
      'security/detect-non-literal-regexp': 'warn',
      'security/detect-non-literal-require': 'error',
      'security/detect-possible-timing-attacks': 'warn',
      'security/detect-pseudoRandomBytes': 'error',
      'security/detect-unsafe-regex': 'error',
      'security/detect-object-injection': 'off', // too many false positives; replaced by targeted Opengrep rule
      'regexp/no-super-linear-backtracking': 'error',
      'regexp/no-super-linear-move': 'warn',
      'no-unsanitized/method': 'error',
      'no-unsanitized/property': 'error',
    },
  },
);
