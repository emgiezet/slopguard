# AP-PY-MAINT-002 — Mutable default arguments

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain]

## Summary
Default argument values are evaluated once at function definition time. Using a mutable object like `[]` or `{}` as a default means all callers share the same object, causing unexpected mutations across calls.

## Do Not Write
```python
def add_item(item, collection=[]):
    collection.append(item)
    return collection
```

## Instead Write
```python
def add_item(item, collection=None):
    if collection is None:
        collection = []
    collection.append(item)
    return collection
```

## Detection
- ruff: `B006`

