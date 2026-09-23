# AP-TS-PERF-001 — Incorrect useEffect dependencies or setState loop

**Category:** performance | **Severity:** error
**Frameworks:** [react]

## Summary
Missing dependencies in `useEffect` cause stale closures; extra dependencies cause infinite re-render loops. List exactly the values the effect reads or writes. Compute derived state during the render phase instead of syncing it with a second `useEffect`.

## Do Not Write
```typescript
useEffect(() => { setCount(count + 1); }, []); // stale count; also infinite loop
```

## Instead Write
```typescript
useEffect(() => { fetchData(userId); }, [userId]);
```

## Detection
- eslint: `react-hooks/exhaustive-deps`
- eslint: `react-hooks/rules-of-hooks`

