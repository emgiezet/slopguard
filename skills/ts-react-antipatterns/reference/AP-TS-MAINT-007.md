# AP-TS-MAINT-007 — Parameters, return types, or aliases typed as `unknown` or `object`

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Using `unknown`, `object`, or `{ [key: string]: unknown }` as a parameter type, return type, or type alias carries no structural information and forces callers to re-validate what the type system should already know. Use a concrete, named interface or type instead. Every boundary that receives external data must validate with a schema library and expose a narrowed type; downstream code should not see `unknown`.

## Do Not Write
```typescript
function process(raw: unknown): void {}
function build(): unknown { return {}; }
type Payload = unknown;
function send(opts: object): void {}
const cache: { [key: string]: unknown } = {};
```

## Instead Write
```typescript
interface RawInput { id: string; value: number }
function process(raw: RawInput): void {}
interface Result { id: string }
function build(): Result { return { id: 'x' }; }
type Payload = { id: string; ts: number };
interface SendOptions { timeout: number }
function send(opts: SendOptions): void {}
const cache: Record<string, string> = {};
```

