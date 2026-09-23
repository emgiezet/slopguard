# AP-RB-SEC-003 — Mass assignment without explicit permit in Rails

**Category:** security | **Severity:** error | **CWE:** CWE-915
**Frameworks:** [rails]

## Summary
Passing `params` directly to `create` or `update` without calling `permit` allows clients to set any attribute, including administrative flags and foreign keys. Always use `params.require(:model).permit(:field1, :field2)`.

## Do Not Write
```ruby
User.create(params[:user])
```

## Instead Write
```ruby
User.create(params.require(:user).permit(:name, :email))
```

## References
- https://cwe.mitre.org/data/definitions/915.html
