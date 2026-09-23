# AP-JVM-SEC-004 — java.util.Random used for security tokens or session IDs

**Category:** security | **Severity:** blocker | **CWE:** CWE-338
**Frameworks:** [plain]

## Summary
`java.util.Random` and `Math.random()` are pseudo-random generators with a predictable seed. Use `java.security.SecureRandom` for any value that must not be guessable, such as tokens, nonces, or session identifiers.

## Do Not Write
```java
String token = Long.toHexString(new Random().nextLong());
```

## Instead Write
```java
byte[] bytes = new byte[32];
new SecureRandom().nextBytes(bytes);
String token = HexFormat.of().formatHex(bytes);
```

## Detection
- opengrep: `slopguard.jvm.insecure-random`

## References
- https://cwe.mitre.org/data/definitions/338.html
