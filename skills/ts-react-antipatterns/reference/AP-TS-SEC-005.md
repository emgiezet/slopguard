# AP-TS-SEC-005 — Secrets or API keys in frontend bundle or VITE_*/NEXT_PUBLIC_* env vars

**Category:** security | **Severity:** blocker | **CWE:** CWE-798
**Frameworks:** [react, plain]

## Summary
Any value prefixed `VITE_` or `NEXT_PUBLIC_` is baked into the client bundle and visible to everyone. Backend-only credentials must never be referenced in frontend code. Use a backend proxy endpoint to make authenticated third-party API calls.

## Do Not Write
```typescript
const key = import.meta.env.VITE_STRIPE_SECRET_KEY; // exposed in bundle
```

## Instead Write
```typescript
// POST /api/payments → server uses process.env.STRIPE_SECRET_KEY
const result = await fetch('/api/payments', { method: 'POST', body });
```

## Detection
- betterleaks: `generic-api-key`

## References
- https://cwe.mitre.org/data/definitions/798.html
