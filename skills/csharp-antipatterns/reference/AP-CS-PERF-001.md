# AP-CS-PERF-001 — async void methods

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain, aspnetcore]

## Summary
An `async void` method cannot be awaited; any exception it throws goes unobserved and typically crashes the process. Only event handlers may use `async void`. All other async methods must return `Task` or `Task<T>`.

## Do Not Write
```csharp
public async void ProcessAsync() { await DoWork(); }
```

## Instead Write
```csharp
public async Task ProcessAsync() { await DoWork(); }
```

