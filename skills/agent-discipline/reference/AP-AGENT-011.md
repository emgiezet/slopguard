# AP-AGENT-011 — Clearing a finding without establishing the guarantee it protects

**Category:** agent | **Severity:** warn

## Summary
A warning is a convenient target — it disappears when the flagged token is gone, whether or not the program gained anything. Replacing a broad parameter type with one derived from the caller clears the type warning while the input stays unvalidated; deleting a `typeof` guard clears the pattern while the message is still dispatched unparsed; moving a cast one line up, or commenting "already validated", changes nothing the runtime can see. A finding is resolved when the program can show what the rule asked for — the value is parsed or narrowed at its source, the failure path is handled and has a test that exercises it — not when the linter stops mentioning it.

## Do Not Write
```
// before: handler(msg: object)             — AP-TS-MAINT-001 on `object`
// after:  handler(msg: ReturnType<typeof resolve>)   — warning gone, msg still unparsed
// before: if (typeof msg.type !== 'string') return;  dispatch(msg);
// after:  dispatch(msg);                               — check gone, defect kept
```

## Instead Write
```
// after:  const cmd = CommandSchema.parse(msg);  dispatch(cmd);
//         + a test that feeds a malformed msg and asserts dispatch is not called
```

