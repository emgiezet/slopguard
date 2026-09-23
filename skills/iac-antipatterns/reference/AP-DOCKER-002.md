# AP-DOCKER-002 — Container runs as root user

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
Running application processes as root inside a container means a process escape grants root access to the host kernel namespace. Always create a dedicated non-root user and switch to it with `USER` before the final `CMD` or `ENTRYPOINT`.

## Do Not Write
```yaml
FROM node:20-alpine
COPY . .
CMD ["node", "server.js"]
# process runs as root
```

## Instead Write
```yaml
FROM node:20-alpine
RUN addgroup -S app && adduser -S app -G app
COPY --chown=app:app . .
USER app
CMD ["node", "server.js"]
```

## Detection
- hadolint: `DL3002`

