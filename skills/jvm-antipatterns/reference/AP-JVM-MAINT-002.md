# AP-JVM-MAINT-002 — Calling System.exit or throwing RuntimeException from library code

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain]

## Summary
Library code that calls `System.exit` takes control away from the application and makes unit testing impossible. Throw a checked exception or a domain-specific runtime exception and let the application entry point decide how to handle it.

## Do Not Write
```java
public Config load(String path) {
    if (!file.exists()) { System.exit(1); }
}
```

## Instead Write
```java
public Config load(String path) throws ConfigException {
    if (!file.exists()) { throw new ConfigException("Config not found: " + path); }
}
```

