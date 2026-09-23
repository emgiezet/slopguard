# AP-JVM-SEC-005 — TrustManager that accepts all certificates

**Category:** security | **Severity:** blocker | **CWE:** CWE-295
**Frameworks:** [plain]

## Summary
Implementing `TrustManager` with an empty `checkServerTrusted` method disables TLS certificate validation, exposing all connections to man-in-the-middle attacks. Use the default `TrustManagerFactory` or supply a properly loaded `KeyStore`.

## Do Not Write
```java
X509TrustManager tm = new X509TrustManager() {
  public void checkServerTrusted(X509Certificate[] c, String a) { /* accepts all */ }
};
```

## Instead Write
```java
TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
tmf.init((KeyStore) null); // loads default JVM trust store
```

## References
- https://cwe.mitre.org/data/definitions/295.html
