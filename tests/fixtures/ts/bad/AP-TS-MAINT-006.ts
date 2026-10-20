// Bad: known value widened to unknown then asserted back — triggers AP-TS-MAINT-006
//   UC-5: no-known-value-widening + no-widen-then-assert

const obj = { id: 'abc' };
const w: unknown = obj;              // no-known-value-widening
const result = w as { id: string };  // no-widen-then-assert
export { result };
