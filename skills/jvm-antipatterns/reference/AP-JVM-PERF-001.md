# AP-JVM-PERF-001 — N+1 queries — loading associations in a loop without eager fetch

**Category:** performance | **Severity:** error
**Frameworks:** [spring, hibernate, quarkus]

## Summary
Accessing a JPA/Hibernate relationship inside a loop issues one SELECT per entity, multiplying database round-trips by the result set size. Use JOIN FETCH in JPQL, entity graphs, or a `@BatchSize` annotation to fetch associations in bulk.

## Do Not Write
```java
for (Order o : orderRepo.findAll()) {
    System.out.println(o.getCustomer().getName()); // N queries
}
```

## Instead Write
```java
List<Order> orders = em.createQuery(
    "SELECT o FROM Order o JOIN FETCH o.customer", Order.class).getResultList();
```

