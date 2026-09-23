# AP-TS-PERF-003 — Components defined inside another component or new objects in context value

**Category:** performance | **Severity:** error
**Frameworks:** [react]

## Summary
Defining a component inside a render function recreates it on every render, causing its subtree to remount and losing state. Creating a new object literal as the context `value` also triggers re-renders for all consumers on every parent render. Move component definitions to module scope and memoize context values.

## Do Not Write
```typescript
function Page() {
  function Row({ item }) { return <li>{item.name}</li>; }
  return <ul>{items.map(i => <Row key={i.id} item={i} />)}</ul>;
}
```

## Instead Write
```typescript
function Row({ item }) { return <li>{item.name}</li>; } // module scope
function Page() {
  return <ul>{items.map(i => <Row key={i.id} item={i} />)}</ul>;
}
```

## Detection
- eslint: `react/no-unstable-nested-components`
- eslint: `react/jsx-no-constructed-context-values`

