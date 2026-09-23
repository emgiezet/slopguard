# AP-TS-PERF-002 — Array index used as React key in dynamic lists

**Category:** performance | **Severity:** warn
**Frameworks:** [react]

## Summary
Using the array index as a key means React cannot distinguish reordered or removed items from changed items, causing incorrect reconciliation and input state loss. Use a stable, unique identifier from the data.

## Do Not Write
```typescript
items.map((item, i) => <Row key={i} item={item} />)
```

## Instead Write
```typescript
items.map((item) => <Row key={item.id} item={item} />)
```

## Detection
- eslint: `react/no-array-index-key`

