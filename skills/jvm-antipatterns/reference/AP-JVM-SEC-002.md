# AP-JVM-SEC-002 — Java native deserialization with ObjectInputStream on external data

**Category:** security | **Severity:** blocker | **CWE:** CWE-502
**Frameworks:** [plain]

## Summary
Deserializing attacker-controlled bytes with `ObjectInputStream` can trigger gadget chains that execute arbitrary code via magic methods. Replace native serialization with JSON, Protocol Buffers, or a safe alternative; if native deserialization is unavoidable, use a `SerialKiller` filter.

## Do Not Write
```java
ObjectInputStream ois = new ObjectInputStream(request.getInputStream());
MyObject obj = (MyObject) ois.readObject();
```

## Instead Write
```java
MyObject obj = objectMapper.readValue(request.getInputStream(), MyObject.class);
```

## Detection
- opengrep: `slopguard.jvm.object-deserialize`

## References
- https://cwe.mitre.org/data/definitions/502.html
