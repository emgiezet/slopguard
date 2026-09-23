# AP-TF-007 — RDS without deletion_protection or automated backups

**Category:** maintainability | **Severity:** warn
**Frameworks:** [aws]

## Summary
An RDS instance without `deletion_protection = true` can be destroyed by a single `terraform destroy` or an accidental Terraform run. Automated backups are disabled by default; set `backup_retention_period` to at least 7 days.

## Do Not Write
```hcl
resource "aws_db_instance" "app" { backup_retention_period = 0 }
```

## Instead Write
```hcl
resource "aws_db_instance" "app" {
  deletion_protection = true; backup_retention_period = 7
}
```

