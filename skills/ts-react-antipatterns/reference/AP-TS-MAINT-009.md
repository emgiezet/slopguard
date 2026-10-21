# AP-TS-MAINT-009 — Whole-module mock replaces the module contract instead of targeting one export

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Replacing an entire module with jest.mock() or vi.mock() couples the test to the module's internal structure rather than its public contract. Any refactor that moves a function to a different file breaks every test that mocks the module, even when the behavior is unchanged. Use vi.spyOn or jest.spyOn to replace only the specific export the test needs to control; the rest of the module runs its real implementation.

## Do Not Write
```typescript
jest.mock('../auth');
```

## Instead Write
```typescript
import * as auth from '../auth';
vi.spyOn(auth, 'getUser').mockReturnValue(fakeUser);
```

