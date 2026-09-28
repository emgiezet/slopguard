# AP-AUTH-001 — Non-CSPRNG or sub-128-bit source for session, reset, or API tokens

**Category:** security | **Severity:** blocker | **CWE:** CWE-330, CWE-338
**Frameworks:** [plain]

## Summary
Session, API, and password-reset tokens generated from a non-cryptographic source (math/rand, Math.random, random.random) or with fewer than 128 bits of entropy are predictable and can be forged. Always use a CSPRNG — crypto/rand in Go, secrets.token_urlsafe(32) in Python, crypto.randomBytes(32) in Node.js. Per-language forms are covered in AP-PHP-SEC-006, AP-NODE-SEC-006, AP-PY-SEC-006, AP-GO-SEC-004, AP-JVM-SEC-004, and AP-RB-SEC-006.

## Do Not Write
```
import "math/rand"
token := strconv.Itoa(rand.Intn(999999)) // 20 bits, predictable
```

## Instead Write
```
import "crypto/rand"
b := make([]byte, 32)                    // 256 bits
if _, err := rand.Read(b); err != nil { return err }
token := hex.EncodeToString(b)
```

## References
- https://cwe.mitre.org/data/definitions/330.html
- https://cwe.mitre.org/data/definitions/338.html
