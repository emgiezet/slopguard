# AP-CS-SEC-003 — Process.Start with user-supplied string command

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [plain, aspnetcore]

## Summary
Calling `Process.Start` with a command string that includes user input enables command injection. Pass arguments as a separate string, not embedded in the file name, and avoid invoking a shell (`cmd.exe /c`) with user data.

## Do Not Write
```csharp
Process.Start("cmd.exe", $"/c convert {userFile} output.png");
```

## Instead Write
```csharp
var psi = new ProcessStartInfo("convert") { Arguments = $"\"{userFile}\" output.png" };
Process.Start(psi);
```

## Detection
- opengrep: `slopguard.cs.process-start-user-input`

## References
- https://cwe.mitre.org/data/definitions/78.html
