# AP-TS-PERF-004 — fetch in useEffect without abort controller or race condition handling

**Category:** performance | **Severity:** warn
**Frameworks:** [react]

## Summary
A `useEffect` that fetches data without an `AbortController` cannot cancel the in-flight request when the component unmounts or when a newer request is initiated, causing stale state updates and memory leaks. Use `AbortController` or a data-fetching library like `SWR` or `TanStack Query`.

## Do Not Write
```typescript
useEffect(() => { fetch('/api/data').then(r => r.json()).then(setData); }, [id]);
```

## Instead Write
```typescript
useEffect(() => {
  const ctrl = new AbortController();
  fetch('/api/data', { signal: ctrl.signal }).then(r => r.json()).then(setData);
  return () => ctrl.abort();
}, [id]);
```

