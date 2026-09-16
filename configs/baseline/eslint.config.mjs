// @ts-check
import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import security from 'eslint-plugin-security';
import regexp from 'eslint-plugin-regexp';
import noUnsanitized from 'eslint-plugin-no-unsanitized';
import n from 'eslint-plugin-n';

// Plugins registered explicitly + rules listed explicitly:
// preset names in flat config change between plugin versions; rule names rarely do.
const TYPED = process.env.SLOPGUARD_TYPED_LINT === '1';

export default defineConfig(
  { ignores: ['**/dist/**', '**/build/**', '**/coverage/**', '**/*.min.js', '**/vendor/**'] },

  // --- common for JS/TS ---
  {
    files: ['**/*.{js,mjs,cjs,jsx,ts,mts,cts,tsx}'],
    extends: [js.configs.recommended],
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

  // --- TypeScript ---
  {
    files: ['**/*.{ts,mts,cts,tsx}'],
    extends: [TYPED ? tseslint.configs.recommendedTypeChecked : tseslint.configs.recommended],
    languageOptions: TYPED
      ? { parserOptions: { projectService: true, tsconfigRootDir: process.cwd() } }
      : {},
    rules: {
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/no-non-null-assertion': 'warn',
      '@typescript-eslint/ban-ts-comment': ['error', {
        'ts-expect-error': 'allow-with-description',
        minimumDescriptionLength: 10,
      }],
      ...(TYPED ? {
        '@typescript-eslint/no-floating-promises': 'error',
        '@typescript-eslint/no-misused-promises': 'error',
        '@typescript-eslint/no-implied-eval': 'error',
        '@typescript-eslint/only-throw-error': 'error',
        '@typescript-eslint/switch-exhaustiveness-check': 'error',
      } : {}),
    },
  },

  // --- React ---
  {
    files: ['**/*.{jsx,tsx}'],
    plugins: { react, 'react-hooks': reactHooks },
    settings: { react: { version: 'detect' } },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',
      'react/no-danger': 'error',
      'react/jsx-no-script-url': 'error',
      'react/jsx-no-target-blank': 'error',
      'react/no-unstable-nested-components': 'error',
      'react/jsx-no-constructed-context-values': 'warn',
      'react/no-array-index-key': 'warn',
    },
  },

  // --- Node.js (only when Node backend detected; dispatcher sets SLOPGUARD_NODE_GLOBS) ---
  {
    files: (process.env.SLOPGUARD_NODE_GLOBS ?? 'server/**,api/**,src/server/**').split(','),
    plugins: { n },
    rules: {
      'n/no-deprecated-api': 'error',
      'n/no-sync': 'error',
      'n/no-process-exit': 'warn',
    },
  },

  // --- tests and scripts: relaxed ---
  {
    files: ['**/*.{test,spec}.{js,ts,jsx,tsx}', '**/__tests__/**', 'scripts/**'],
    rules: {
      'n/no-sync': 'off',
      'security/detect-non-literal-fs-filename': 'off',
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
);
