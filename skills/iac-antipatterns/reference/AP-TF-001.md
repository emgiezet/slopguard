# AP-TF-001 — Public S3 bucket or missing Block Public Access

**Category:** security | **Severity:** blocker
**Frameworks:** [aws]

## Summary
An S3 bucket without Block Public Access settings can be made publicly accessible through bucket or object ACLs. Always attach `aws_s3_bucket_public_access_block` with all four flags set to `true`.

## Do Not Write
```hcl
resource "aws_s3_bucket" "data" { bucket = "my-data" }
# No aws_s3_bucket_public_access_block
```

## Instead Write
```hcl
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true; block_public_policy  = true
  ignore_public_acls      = true; restrict_public_buckets = true
}
```

