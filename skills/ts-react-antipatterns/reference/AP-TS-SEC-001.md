# AP-TS-SEC-001 — dangerouslySetInnerHTML or innerHTML with user data

**Category:** security | **Severity:** blocker | **CWE:** CWE-79
**Frameworks:** [react]

## Summary
Setting `innerHTML` or `dangerouslySetInnerHTML` with unsanitized user content enables cross-site scripting. Render plain text as text nodes; run rich-text content through a strict allowlist sanitizer like DOMPurify before injecting HTML.

## Do Not Write
```typescript
<div dangerouslySetInnerHTML={{ __html: post.body }} />
```

## Instead Write
```typescript
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(post.body) }} />
```

## Detection
- eslint: `react/no-danger`
- eslint: `no-unsanitized/method`
- eslint: `no-unsanitized/property`

## References
- https://cwe.mitre.org/data/definitions/79.html
