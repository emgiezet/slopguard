// Good: use the original typed value directly; assert only on truly external data — UC-6 (no AP-TS-MAINT-006)
const obj = { id: 'abc' };
// OK: use obj directly without widening to unknown
const result = obj;

// OK: assertion on a value that is already unknown from an external boundary
declare function parsePayload(): unknown;
const raw = parsePayload();
// SAFETY: parsePayload() returns { id: string } from the validated session token
const parsed = raw as { id: string };

export { result, parsed };
