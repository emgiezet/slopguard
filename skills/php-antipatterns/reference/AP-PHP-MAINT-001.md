# AP-PHP-MAINT-001 — Validation and business logic inside a controller

**Category:** maintainability | **Severity:** warn
**Frameworks:** [laravel, symfony]

## Summary
Controllers should orchestrate; they must not contain validation rules or business logic. Extract validation to FormRequest classes and domain logic to service or action classes.

## Do Not Write
```php
public function store(Request $request) {
    $request->validate(['email' => 'required|email']);
    if (User::whereEmail($request->email)->exists()) abort(409);
    // ... business logic
}
```

## Instead Write
```php
public function store(RegisterUserRequest $request, RegisterUser $action) {
    return $action->execute($request->validated());
}
```

