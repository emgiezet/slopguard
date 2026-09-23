# AP-DOCKER-005 — Build tools or dev dependencies in the final image

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Installing compilers, package managers, or test frameworks in the final production image bloats image size and increases the attack surface. Use a multi-stage build to compile in a builder stage and copy only the final artifact into a minimal runtime image.

## Do Not Write
```yaml
FROM node:20
RUN npm install        # dev deps included
COPY . .
RUN npm run build
CMD ["node", "dist/server.js"]
```

## Instead Write
```yaml
FROM node:20 AS builder
COPY package*.json ./; RUN npm ci
COPY . .; RUN npm run build
FROM node:20-alpine AS runtime
COPY --from=builder /app/dist /app/dist
USER node
CMD ["node", "/app/dist/server.js"]
```

