# AP-RB-SEC-004 — Shell injection via string interpolation in backticks or system

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [rails, plain]

## Summary
Embedding user-controlled values in backtick expressions or `system(string)` allows shell metacharacter injection. Use `Open3.capture2e` with an explicit argument array so the shell is never invoked.

## Do Not Write
```ruby
`convert #{params[:file]} output.png`
system("rm -rf #{path}")
```

## Instead Write
```ruby
out, status = Open3.capture2e('convert', params[:file], 'output.png')
```

## Detection
- opengrep: `slopguard.ruby.shell-injection-interpolation`

## References
- https://cwe.mitre.org/data/definitions/78.html
