# AP-TF-004 — IAM policy with Action * or Resource *

**Category:** security | **Severity:** blocker
**Frameworks:** [aws]

## Summary
Wildcard IAM actions or resources grant excessive permissions that violate the principle of least privilege. Define the narrowest set of allowed actions and the specific resource ARNs the role needs.

## Do Not Write
```hcl
statement { actions = ["*"]; resources = ["*"] }
```

## Instead Write
```hcl
statement {
  actions = ["s3:GetObject", "s3:PutObject"]
  resources = ["arn:aws:s3:::my-bucket/*"]
}
```

