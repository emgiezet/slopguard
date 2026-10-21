// Bad: whole-module mock — triggers AP-TS-MAINT-009
//   UC-3: no-module-mocking

jest.mock('../auth');   // replaces entire module; couples test to internal structure

export {};
