// Good: as const and SAFETY-commented assertions — UC-6 (no AP-TS-MAINT-005 or -006)
type UserId = string;

const FLAGS = ['read', 'write'] as const;  // as const is allowed

// Simulate input from an external boundary (truly unknown, not widened)
declare function readClaim(): unknown;
const raw = readClaim();

// SAFETY: readClaim() always returns a non-empty string from the validated JWT
const id = raw as UserId;

export { FLAGS, id };
