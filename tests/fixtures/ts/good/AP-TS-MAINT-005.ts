// Good: as const and SAFETY-commented assertions — UC-6 (no AP-TS-MAINT-005 or -006)
type UserId = string;

const FLAGS = ['read', 'write'] as const;  // as const is allowed

// Simulate input from an external boundary (truly unknown, not widened)
declare const raw: unknown;

// SAFETY: the validated JWT claim at this boundary is always a non-empty string
const id = raw as UserId;

export { FLAGS, id };
