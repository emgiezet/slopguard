# AP-TF-003 — Unencrypted EBS volumes, RDS instances, or S3 objects

**Category:** security | **Severity:** blocker
**Frameworks:** [aws]

## Summary
EBS volumes, RDS instances, and S3 buckets without server-side encryption store data in plaintext at rest. Enable encryption on every resource that may hold sensitive data; use a customer-managed KMS key for compliance-sensitive workloads.

## Do Not Write
```hcl
resource "aws_db_instance" "app" { storage_encrypted = false }
```

## Instead Write
```hcl
resource "aws_db_instance" "app" { storage_encrypted = true; kms_key_id = aws_kms_key.rds.arn }
```

