# AP-AUTH-010 — OAuth2/OIDC code flow without state and PKCE, or with a non-exact redirect_uri match

**Category:** security | **Severity:** blocker | **CWE:** CWE-352, CWE-601
**Frameworks:** [plain]

## Summary
An OAuth2 authorization-code flow without the state parameter is vulnerable to cross-site request forgery, letting an attacker trick a user into linking their account to the attacker's identity. Without PKCE, an intercepted authorization code can be exchanged for tokens by a third party. Always generate a cryptographically random state value, include a PKCE code challenge, and match the redirect_uri against an exact server-side allowlist.

## Do Not Write
```
// no state, no PKCE; redirect_uri taken from request
const url = provider.authUrl({
    client_id:    CLIENT_ID,
    redirect_uri: req.query.redirect_uri as string,
    response_type: 'code',
});
```

## Instead Write
```
const state     = crypto.randomBytes(16).toString('hex');
const verifier  = crypto.randomBytes(32).toString('base64url');
const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
session.oauthState = state; session.pkceVerifier = verifier;
const url = provider.authUrl({
    client_id: CLIENT_ID, redirect_uri: ALLOWED_REDIRECT,
    state, code_challenge: challenge, code_challenge_method: 'S256',
});
```

## References
- https://cwe.mitre.org/data/definitions/352.html
- https://cwe.mitre.org/data/definitions/601.html
