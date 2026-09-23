# AP-TS-SEC-003 — Session tokens stored in localStorage

**Category:** security | **Severity:** error | **CWE:** CWE-922
**Frameworks:** [react, plain]

## Summary
Tokens in `localStorage` are accessible to any script on the page, including injected third-party code. Store session tokens in `HttpOnly; Secure; SameSite=Strict` cookies managed by the server, which are invisible to JavaScript.

## Do Not Write
```typescript
localStorage.setItem('auth_token', response.token);
```

## Instead Write
```typescript
// Server sets: Set-Cookie: session=...; HttpOnly; Secure; SameSite=Strict
// Client just calls the API; cookie is sent automatically
```

## Detection
- opengrep: `slopguard.react.token-in-localstorage`

## References
- https://cwe.mitre.org/data/definitions/922.html
