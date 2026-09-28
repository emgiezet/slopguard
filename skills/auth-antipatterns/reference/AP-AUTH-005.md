# AP-AUTH-005 — JWT accepted without pinning the algorithm; iss, aud, exp not verified; HMAC/RSA key confusion

**Category:** security | **Severity:** blocker | **CWE:** CWE-347
**Frameworks:** [plain]

## Summary
Accepting a JWT without an explicit algorithm allowlist enables the "alg: none" attack (signature stripped entirely) and the HMAC/RSA confusion attack where the server's RSA public key is used as an HMAC secret. Always pass a fixed algorithms array to the verification call and validate the iss, aud, and exp claims every time. Never derive the verification key from the token's own header.

## Do Not Write
```
// no algorithm pin; iss and aud not checked
const payload = jwt.verify(token, publicKey);
```

## Instead Write
```
const payload = jwt.verify(token, publicKey, {
    algorithms: ['RS256'],
    issuer:     'https://auth.example.com',
    audience:   'api.example.com',
});
```

## References
- https://cwe.mitre.org/data/definitions/347.html
