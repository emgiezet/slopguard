# AP-AGENT-005 — Reading credential files or private keys

**Category:** agent | **Severity:** blocker | **CWE:** CWE-522

## Summary
Reading `.env` files, private keys, AWS credentials, kubeconfig, or any file in a secrets directory exposes production credentials that should never enter the model context. These reads are denied unconditionally.

## Do Not Write
Read(".env")
cat ~/.aws/credentials
cat id_rsa

## Instead Write
# Use environment variable names or placeholder values; secrets stay out of context

## References
- https://cwe.mitre.org/data/definitions/522.html
