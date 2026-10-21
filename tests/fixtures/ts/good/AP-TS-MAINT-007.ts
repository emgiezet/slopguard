// Good: concrete named types — UC-7 (no AP-TS-MAINT-007 findings)

interface RawInput { id: string; value: number }
function process(raw: RawInput): void { void raw; }

interface Result { id: string }
function build(): Result { return { id: 'x' }; }

type Payload = { id: string; ts: number };

interface SendOptions { timeout: number }
function send(opts: SendOptions): void { void opts; }

const cache: Record<string, string> = {};

export { process, build, send, cache };
export type { Payload };
