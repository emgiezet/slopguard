# AP-GO-MAINT-004 — Unchecked type assertion x.(T)

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain]

## Summary
A bare type assertion `x.(T)` panics at runtime if the dynamic type is not `T`. Always use the two-value form `v, ok := x.(T)` and check `ok` before using `v`.

## Do Not Write
val := data["key"].(string) // panics if not a string

## Instead Write
val, ok := data["key"].(string)
if !ok { return fmt.Errorf("key is not a string") }

