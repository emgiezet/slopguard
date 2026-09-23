# AP-TF-006 — Unpinned provider or module versions

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
Unpinned providers or modules (`source = "hashicorp/aws"` with no version constraint) can pull in breaking or malicious releases when you run `terraform init -upgrade`. Pin every provider and module to a specific version constraint.

## Do Not Write
```hcl
terraform { required_providers { aws = { source = "hashicorp/aws" } } }
```

## Instead Write
```hcl
terraform {
  required_providers { aws = { source = "hashicorp/aws"; version = "~> 5.56" } }
}
```

