# AP-TF-005 — Hard-coded secrets in Terraform files or non-sensitive outputs

**Category:** security | **Severity:** blocker | **CWE:** CWE-798
**Frameworks:** [aws, plain]

## Summary
Storing credentials in `.tf` or `.tfvars` files commits them to version control. Mark any output that contains a sensitive value with `sensitive = true` to prevent it appearing in plan output. Load secrets from environment variables or a secrets manager data source.

## Do Not Write
```hcl
variable "db_password" { default = "hunter2" }
```

## Instead Write
```hcl
variable "db_password" { type = string; sensitive = true }
# value supplied via TF_VAR_db_password or AWS Secrets Manager data source
```

## Detection
- betterleaks: `generic-api-key`

## References
- https://cwe.mitre.org/data/definitions/798.html
