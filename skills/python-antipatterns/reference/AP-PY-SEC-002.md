# AP-PY-SEC-002 — subprocess with shell=True or os.system with user input

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [plain]

## Summary
Passing `shell=True` lets the shell interpret metacharacters in the command string, enabling injection. Use a list of arguments with `shell=False` (the default) so the OS invokes the program directly.

## Do Not Write
```python
subprocess.run(f"convert {filename} output.png", shell=True)
```

## Instead Write
```python
subprocess.run(['convert', filename, 'output.png'], check=True)
```

## Detection
- ruff: `S602`
- ruff: `S605`

## References
- https://cwe.mitre.org/data/definitions/78.html
