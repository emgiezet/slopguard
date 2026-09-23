# AP-RB-SEC-005 — SQL string interpolation in ActiveRecord queries

**Category:** security | **Severity:** blocker | **CWE:** CWE-89
**Frameworks:** [rails]

## Summary
Interpolating variables into `where`, `find_by_sql`, or `execute` strings allows SQL injection. Use the hash syntax or the `?` placeholder form to let ActiveRecord parameterise the query.

## Do Not Write
```ruby
User.where("email = '#{params[:email]}'")
```

## Instead Write
```ruby
User.where(email: params[:email])
User.where('email = ?', params[:email])
```

## References
- https://cwe.mitre.org/data/definitions/89.html
