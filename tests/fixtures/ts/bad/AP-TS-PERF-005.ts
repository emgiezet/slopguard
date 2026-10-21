// Bad: O(n²) reduce accumulator copying — triggers AP-TS-PERF-005
//   UC-1: no-reduce-accumulator-copy

interface Item { id: string; value: number }

declare const items: Item[];

// Copies the entire accumulator on every iteration — O(n²) work.
const index = items.reduce<Record<string, Item>>(
    (acc, x) => Object.assign({}, acc, { [x.id]: x }),
    {},
);

export { index };
