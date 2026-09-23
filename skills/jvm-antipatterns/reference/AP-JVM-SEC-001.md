# AP-JVM-SEC-001 — JDBC query built by string concatenation or formatting

**Category:** security | **Severity:** blocker | **CWE:** CWE-89
**Frameworks:** [plain, spring, quarkus, jooq]

## Summary
Building a SQL string by concatenating user-supplied values and executing it with `Statement.executeQuery` or `Connection.createStatement` allows an attacker to alter the query structure. Always use `PreparedStatement` with `?` placeholders or a typed query builder.

## Do Not Write
```java
String sql = "SELECT * FROM users WHERE email = '" + email + "'";
conn.createStatement().executeQuery(sql);
```

## Instead Write
```java
PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE email = ?");
ps.setString(1, email);
ResultSet rs = ps.executeQuery();
```

## Detection
- opengrep: `slopguard.jvm.jdbc-string-concat`

## References
- https://cwe.mitre.org/data/definitions/89.html
