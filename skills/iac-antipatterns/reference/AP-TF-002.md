# AP-TF-002 — Security group open to 0.0.0.0/0 on admin or database ports

**Category:** security | **Severity:** blocker
**Frameworks:** [aws]

## Summary
Allowing inbound traffic from any IP on ports like 22 (SSH), 3389 (RDP), 3306 (MySQL), or 5432 (Postgres) exposes those services to the entire internet. Restrict ingress to known CIDR ranges or VPC-internal access only.

## Do Not Write
```hcl
ingress { from_port = 22; to_port = 22; cidr_blocks = ["0.0.0.0/0"] }
```

## Instead Write
```hcl
ingress { from_port = 22; to_port = 22; cidr_blocks = ["10.0.0.0/8"] }
```

## Detection
- checkov: `CKV_AWS_25`

