/**
 * omp.mjs — slop-guard extension for Oh My Pi (omp).
 *
 * Translates omp tool_call events into the existing bash policy subcommands so
 * slop-guard enforces under omp exactly as it does under Claude Code and Grok.
 * Zero policy logic lives here: every decision comes from bin/slopguard.
 */
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const PLUGIN_ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const SLOPGUARD   = join(PLUGIN_ROOT, 'bin', 'slopguard');
const TIMEOUT_MS  = 5_000;

// ── Pure helpers (exported for tests) ─────────────────────────────────────────

/**
 * Strip a line-range selector from a Read tool path.
 * "src/foo.ts:10-20"  → "src/foo.ts"
 * "src/foo.ts:50+150" → "src/foo.ts"
 * ".env:1-5"          → ".env"
 * "src/foo.ts"        → "src/foo.ts"  (unchanged)
 */
export function stripReadSelector(path) {
  return (path ?? '').replace(/:[0-9][0-9,+\-]*$/, '');
}

/**
 * Extract the file path from the hashline header of an omp edit patch.
 * Header format: [path#XXXX] on the first line, where XXXX is exactly 4 hex chars.
 * Returns '' when absent or malformed — caller should still send the content
 * (secret scanning applies even without a clean path).
 */
export function editPathFromPatch(patchText) {
  const first = (patchText ?? '').split('\n')[0] ?? '';
  const m = first.match(/^\[(.+?)#[0-9A-Fa-f]{4}\]$/);
  return m ? m[1] : '';
}

/**
 * Translate policy stdout into a decision object.
 *
 * Policy output forms:
 *   {"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":R}}
 *   {"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":R}}
 *   {"hookSpecificOutput":{"additionalContext":C}}
 *   (empty / non-JSON) → allow
 *
 * Returns { decision: 'allow'|'deny'|'ask'|'context', reason?, context?, unparseable? }
 */
export function parseDecision(stdout) {
  const text = (stdout ?? '').trim();
  if (!text) return { decision: 'allow' };

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { decision: 'allow', unparseable: true };
  }

  const hso = parsed?.hookSpecificOutput;
  if (!hso) return { decision: 'allow' };

  if (hso.additionalContext) {
    return { decision: 'context', context: hso.additionalContext };
  }

  const d = hso.permissionDecision;
  const r = hso.permissionDecisionReason ?? '';

  if (d === 'deny' || d === 'ask') {
    return { decision: d, reason: r };
  }

  return { decision: 'allow' };
}

// ── Subprocess runner ─────────────────────────────────────────────────────────

function buildEnv(ctx) {
  const env = { ...process.env };
  env.CLAUDE_PLUGIN_ROOT = PLUGIN_ROOT;
  // Preserve caller-supplied CLAUDE_PLUGIN_DATA; otherwise derive from XDG / HOME.
  env.CLAUDE_PLUGIN_DATA =
    process.env.CLAUDE_PLUGIN_DATA ??
    `${process.env.XDG_DATA_HOME ?? (process.env.HOME + '/.local/share')}/claude/plugins/slop-guard`;
  if (ctx && !ctx.hasUI) env.AISDLC_HEADLESS = '1';
  return env;
}

/**
 * Spawn `bin` <subcommand> with JSON payload on stdin.
 * Hard-kills the child after TIMEOUT_MS.
 * Rejects on spawn errors (ENOENT / EACCES) so the caller can log and fail open.
 * Resolves for all other outcomes, including non-zero exit codes from the policy.
 */
function defaultRun(bin, subcommand, payload, env) {
  return new Promise((resolve, reject) => {
    let settled = false;

    const child = execFile(bin, [subcommand], { env }, (err, stdout, stderr) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      // Spawn errors (binary not found or not executable) — reject for caller to handle.
      if (err && (err.code === 'ENOENT' || err.code === 'EACCES')) {
        reject(err);
        return;
      }
      const exitCode = err ? (Number.isInteger(err.code) ? err.code : 1) : 0;
      resolve({ stdout: stdout ?? '', stderr: stderr ?? '', exitCode, timedOut: false });
    });

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      try { child.kill('SIGKILL'); } catch { /* ignore */ }
      resolve({ stdout: '', stderr: '', exitCode: -1, timedOut: true });
    }, TIMEOUT_MS);

    try {
      child.stdin.write(JSON.stringify(payload));
      child.stdin.end();
    } catch {
      // stdin already closed (spawn-error path); the callback will handle the error.
    }
  });
}

// ── Factory ───────────────────────────────────────────────────────────────────

/**
 * slop-guard omp extension factory.
 *
 * @param {object} pi        - omp extension host API
 * @param {object} [_opts]   - internal test hooks only
 * @param {Function} [_opts._runner]    - replaces the subprocess call; (subcommand, payload, env) => Promise
 * @param {string}  [_opts._slopguard] - replaces the binary path (used when _runner is absent)
 */
export default function slopGuardExtension(pi, { _runner, _slopguard } = {}) {
  const bin = _slopguard ?? SLOPGUARD;

  // `run` always has signature (subcommand, payload, env) => Promise<{stdout,stderr,exitCode,timedOut}>.
  const run = _runner ?? ((subcommand, payload, env) => defaultRun(bin, subcommand, payload, env));

  /**
   * Execute a policy subcommand and translate the result to an omp block decision.
   * Returns { block: true, reason } to stop the tool, or undefined to allow it.
   */
  async function exec(subcommand, payload, ctx) {
    let result;
    try {
      result = await run(subcommand, payload, buildEnv(ctx));
    } catch (err) {
      pi.logger?.warn?.(`slop-guard[omp]: spawn failed (${subcommand}): ${err.message} — allowing`);
      return undefined;
    }

    if (result.timedOut) {
      pi.logger?.warn?.(`slop-guard[omp]: ${subcommand} timed out after ${TIMEOUT_MS}ms — allowing`);
      return undefined;
    }

    // exit 2 with stderr text — explicit blocking error (sdlc guard convention).
    if (result.exitCode === 2 && result.stderr.trim()) {
      return { block: true, reason: result.stderr.trim() };
    }

    const d = parseDecision(result.stdout);

    if (d.unparseable) {
      pi.logger?.warn?.(`slop-guard[omp]: unparseable output from ${subcommand} — allowing`);
      return undefined;
    }

    if (d.decision === 'context') {
      pi.sendMessage(d.context);
      return undefined;
    }

    if (d.decision === 'deny') {
      return { block: true, reason: d.reason };
    }

    if (d.decision === 'ask') {
      // Headless: adapter already set AISDLC_HEADLESS=1, so the policy would have
      // emitted deny already. This path handles the rare case where a policy emits
      // 'ask' despite the env var (e.g. a future policy that ignores the flag).
      if (!ctx?.hasUI) {
        return { block: true, reason: d.reason };
      }
      const confirmed = await ctx.ui.confirm(d.reason);
      if (!confirmed) {
        return { block: true, reason: d.reason };
      }
      return undefined; // user confirmed — allow
    }

    return undefined; // allow
  }

  // ── session_start: emit always-on AP-AGENT rules via sendMessage ─────────
  pi.on('session_start', async (_event, ctx) => {
    try {
      const env = buildEnv(ctx ?? { hasUI: false });
      const result = await run('session-start', {}, env);
      if (!result.timedOut && result.stdout.trim()) {
        pi.sendMessage(result.stdout.trim());
      }
    } catch {
      // Non-fatal: session_start failure must never brick the session.
    }
  });

  // ── tool_call: gate Bash / Read / Write / Edit ────────────────────────────
  pi.on('tool_call', async (event, ctx) => {
    const { toolName, input = {} } = event;

    switch (toolName) {
      case 'bash': {
        const payload = {
          tool_name: 'Bash',
          tool_input: { command: input.command ?? '' },
        };
        return exec('pre-bash', payload, ctx);
      }

      case 'read': {
        // Strip optional line selector (":10-20", ":50+150", etc.) from path.
        const filePath = stripReadSelector(input.path ?? '');
        const payload = {
          tool_name: 'Read',
          tool_input: { file_path: filePath },
        };
        return exec('pre-read', payload, ctx);
      }

      case 'write': {
        const payload = {
          tool_name: 'Write',
          tool_input: {
            file_path: input.path ?? '',
            content:   input.content ?? '',
          },
        };
        return exec('pre-write', payload, ctx);
      }

      case 'edit': {
        // The edit tool's `input` field is the full hashline patch text.
        const patchText = input.input ?? '';
        const filePath  = editPathFromPatch(patchText);
        const payload = {
          tool_name: 'Write',
          tool_input: {
            file_path: filePath,
            content:   patchText,
          },
        };
        return exec('pre-write', payload, ctx);
      }

      default:
        // Unknown tool — return immediately with no subprocess call.
        return;
    }
  });
}
