# AP-DOCKER-003 — Secrets in ENV, ARG, or COPY .env

**Category:** security | **Severity:** blocker | **CWE:** CWE-798
**Frameworks:** [plain]

## Summary
Values passed to `ENV` or `ARG` are preserved in every image layer and visible in `docker inspect`. Copying a `.env` file bakes secrets into the image. Inject secrets at runtime via environment variables or a secrets manager; use Docker BuildKit secrets for build-time credentials.

## Do Not Write
```yaml
ARG API_KEY=sk-live-abc123
ENV STRIPE_KEY=$API_KEY
COPY .env /app/.env
```

## Instead Write
```yaml
# Build: docker build --secret id=apikey,src=./secret.txt .
# Runtime: docker run -e STRIPE_KEY=$STRIPE_KEY my-app
```

## Detection
- betterleaks: `generic-api-key`

## References
- https://cwe.mitre.org/data/definitions/798.html
