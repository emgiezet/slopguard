# AP-TS-PERF-005 — O(n²) reduce accumulator copying

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
Copying the accumulator on every reduce iteration (`Object.assign({}, acc, …)`, `Array.from(acc)`, `acc.concat(…)`, `acc.slice()` and similar) copies every earlier result at each step, making the whole operation O(n²). Spread copies (`{ ...acc }`) have the same cost; the pinned ESLint detector reports the non-spread forms only. Mutate a locally owned accumulator and return it.

## Do Not Write
```typescript
const index = items.reduce<Record<string, Item>>((acc, x) => Object.assign({}, acc, { [x.id]: x }), {});
```

## Instead Write
```typescript
const index = items.reduce<Record<string, Item>>((acc, x) => { acc[x.id] = x; return acc; }, {});
```

