# AP-RB-MAINT-002 — Missing frozen_string_literal magic comment

**Category:** performance | **Severity:** warn
**Frameworks:** [rails, plain]

## Summary
Without `# frozen_string_literal: true`, every string literal creates a new mutable object each time the line is executed. Freezing string literals eliminates these allocations for constants used as hash keys, method selectors, or repeated conditions.

## Do Not Write
```ruby
STATUS_ACTIVE = "active"     # new String object each time this constant is read
```

## Instead Write
```ruby
# frozen_string_literal: true
STATUS_ACTIVE = "active"     # interned; no allocation after the first
```

