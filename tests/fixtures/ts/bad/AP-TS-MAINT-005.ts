// Bad: fabricated type evidence — triggers AP-TS-MAINT-005
//   UC-3: no-chained-type-assertions
//   UC-4: require-safety-comment-for-type-assertion

type Foo = { x: number };
type UserId = string;

const y: unknown = {};
const x = (y as unknown) as Foo;  // UC-3: chained assertion

const value: unknown = 'user-42';
const id = value as UserId;       // UC-4: no SAFETY comment above
export { x, id };
