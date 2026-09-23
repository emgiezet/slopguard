# AP-JVM-SEC-003 — Runtime.exec or ProcessBuilder with user-supplied string

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [plain]

## Summary
Passing a user-controlled value to `Runtime.exec(String)` invokes a shell that interprets metacharacters. Use the array form `Runtime.exec(String[])` or `ProcessBuilder` with each argument as a separate element so no shell is invoked.

## Do Not Write
```java
Runtime.getRuntime().exec("convert " + userFile + " output.png");
```

## Instead Write
```java
new ProcessBuilder("convert", userFile, "output.png").start();
```

## Detection
- opengrep: `slopguard.jvm.runtime-exec-concat`

## References
- https://cwe.mitre.org/data/definitions/78.html
