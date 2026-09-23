# AP-CS-SEC-005 — Missing security headers in ASP.NET Core controllers

**Category:** security | **Severity:** warn | **CWE:** CWE-693
**Frameworks:** [aspnetcore]

## Summary
ASP.NET Core does not add security headers (CSP, X-Frame-Options, HSTS) by default. Add a security header middleware early in the pipeline to apply them to every response.

## Do Not Write
```csharp
app.UseRouting();
app.MapControllers();
// No security header middleware
```

## Instead Write
```csharp
app.UseHsts();
app.UseXfo(x => x.Deny());
app.UseCsp(opt => opt.DefaultSources(s => s.Self()));
```

## References
- https://cwe.mitre.org/data/definitions/693.html
