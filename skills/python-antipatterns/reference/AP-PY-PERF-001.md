# AP-PY-PERF-001 — N+1 queries in Django or SQLAlchemy

**Category:** performance | **Severity:** error
**Frameworks:** [django, sqlalchemy]

## Summary
Iterating over a queryset and touching a relation on each object issues one database query per object. Use `select_related` (Django) or `selectinload`/`joinedload` (SQLAlchemy) to fetch related objects in one query.

## Do Not Write
```python
for order in Order.objects.all():
    print(order.customer.name)   # query per order
```

## Instead Write
```python
for order in Order.objects.select_related('customer').all():
    print(order.customer.name)
```

