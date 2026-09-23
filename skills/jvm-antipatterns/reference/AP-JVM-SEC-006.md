# AP-JVM-SEC-006 — Jackson polymorphic deserialization with enableDefaultTyping

**Category:** security | **Severity:** blocker | **CWE:** CWE-502
**Frameworks:** [spring, plain]

## Summary
Calling `enableDefaultTyping` or using `@JsonTypeInfo` with external class names allows an attacker to supply arbitrary class names in JSON, which Jackson then instantiates — enabling remote code execution. Use specific subtypes or a safelist.

## Do Not Write
```java
mapper.enableDefaultTyping(ObjectMapper.DefaultTyping.NON_FINAL);
```

## Instead Write
```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME)
@JsonSubTypes({ @JsonSubTypes.Type(value = Cat.class, name = "cat") })
abstract class Animal {}
```

## References
- https://cwe.mitre.org/data/definitions/502.html
