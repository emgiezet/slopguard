# AP-GO-PERF-004 — Unnecessary allocations — append in loop without prealloc or Sprintf for simple concat

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
Appending to a nil slice inside a loop when the final length is known causes repeated slice resizing. Using `fmt.Sprintf` to concatenate two strings is slower than `+` or `strings.Builder`. Pre-allocate slices and use cheaper string operations.

## Do Not Write
var ids []int64
for _, u := range users { ids = append(ids, u.ID) }
label := fmt.Sprintf("%s_%d", prefix, id)

## Instead Write
ids := make([]int64, 0, len(users))
for _, u := range users { ids = append(ids, u.ID) }
label := prefix + "_" + strconv.FormatInt(id, 10)

## Detection
- golangci-lint: `prealloc`
- golangci-lint: `perfsprint`

