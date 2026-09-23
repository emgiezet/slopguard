# AP-TS-SEC-002 — eval, new Function, or dynamic code execution

**Category:** security | **Severity:** blocker | **CWE:** CWE-95
**Frameworks:** [plain]

## Summary
Calling `eval`, `new Function`, or passing a string to `setTimeout`/`setInterval` evaluates arbitrary code. Use static code paths; if dynamic dispatch is needed, use an explicit map of known operations.

## Do Not Write
```typescript
const fn = new Function('return ' + userInput)();
```

## Instead Write
```typescript
const ops: Record<string, () => number> = { sum, avg };
const result = ops[userOp]?.() ?? 0;
```

## Detection
- eslint: `no-eval`
- eslint: `no-new-func`
- eslint: `security/detect-eval-with-expression`

## References
- https://cwe.mitre.org/data/definitions/95.html
