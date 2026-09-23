# AP-TS-SEC-004 — Unvalidated href or src from user data (javascript: URL)

**Category:** security | **Severity:** blocker | **CWE:** CWE-79
**Frameworks:** [react]

## Summary
Setting `href` or `src` from user data without validating the URL scheme allows `javascript:` URLs that execute code when the link is followed. Validate that the scheme is `https:` or `http:` before using any user-supplied URL.

## Do Not Write
```typescript
<a href={user.website}>Visit</a>  // user.website might be "javascript:alert(1)"
```

## Instead Write
```typescript
const safe = /^https?:\/\//.test(user.website) ? user.website : '#';
<a href={safe}>Visit</a>
```

## Detection
- eslint: `react/jsx-no-script-url`
- eslint: `no-script-url`

## References
- https://cwe.mitre.org/data/definitions/79.html
