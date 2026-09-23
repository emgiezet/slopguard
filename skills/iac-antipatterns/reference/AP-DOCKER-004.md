# AP-DOCKER-004 — curl piped to shell in RUN, or missing pipefail

**Category:** security | **Severity:** blocker
**Frameworks:** [plain]

## Summary
A `RUN` instruction that downloads and immediately executes a script bakes an unverified external dependency into the image. Even without piping to shell, a multi-command `RUN` without `set -o pipefail` can silently succeed when an intermediate command fails.

## Do Not Write
```yaml
RUN curl -sSL https://install.example.com/script.sh | sh
RUN wget -qO- example.com/setup | bash
```

## Instead Write
```yaml
# Download, verify checksum, then execute:
RUN curl -sSLo setup.sh https://example.com/setup.sh \
  && echo "abc123  setup.sh" | sha256sum -c \
  && sh setup.sh
```

## Detection
- opengrep: `slopguard.docker.curl-pipe-shell`
- hadolint: `DL4006`

