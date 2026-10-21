// Bad: unknown/object-typed signatures — triggers AP-TS-MAINT-007
//   UC-1: no-unknown-parameters
//   UC-2: no-unknown-returns
//   UC-1: no-unknown-type-aliases
//   UC-3: no-object-parameters
//   UC-4: no-unsafe-dictionary-type

function process(raw: unknown): void { void raw; }       // UC-1: no-unknown-parameters

function build(): unknown { return {}; }                  // UC-2: no-unknown-returns

type Payload = unknown;                                   // UC-1: no-unknown-type-aliases

function send(opts: object): void { void opts; }          // UC-3: no-object-parameters

const cache: { [key: string]: unknown } = {};             // UC-4: no-unsafe-dictionary-type

export { process, build, send, cache };
export type { Payload };
