# No terraform {} block → tflint: terraform_required_version → AP-TF-MAINT-003
# acl = "public-read"  → checkov: CKV_AWS_57              → AP-TF-SEC-010
# ruleid: tflint.terraform_required_version, checkov.CKV_AWS_57

resource "aws_s3_bucket" "data" {
  bucket = "my-data-bucket"
  acl    = "public-read"
}
