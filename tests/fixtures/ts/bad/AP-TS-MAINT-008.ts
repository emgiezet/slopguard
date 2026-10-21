// Bad: Reflect API bypasses TypeScript type checks — triggers AP-TS-MAINT-008
//   UC-5: no-reflect-get
//   UC-6: no-reflect-apply

const obj = { id: 'user-42' };
const v = Reflect.get(obj, 'id');           // UC-5: no-reflect-get

function fn(x: string): string { return x; }
const arg = 'hello';
const r = Reflect.apply(fn, null, [arg]);   // UC-6: no-reflect-apply

export { v, r };
