// Good: direct property access and typed function calls — UC-7 (no AP-TS-MAINT-008 findings)

const obj = { id: 'user-42' };
const v = obj.id;                           // direct property access, not Reflect.get

function fn(x: string): string { return x; }
const arg = 'hello';
const r = fn(arg);                          // typed call, not Reflect.apply

export { v, r };
