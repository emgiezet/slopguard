// Good: in-place accumulator mutation — UC-2 (no AP-TS-PERF-005 finding)

interface Item { id: string; value: number }

declare const items: Item[];

// Mutates a locally owned accumulator — linear work.
const index = items.reduce<Record<string, Item>>(
    (acc, x) => { acc[x.id] = x; return acc; },
    {},
);

export { index };
