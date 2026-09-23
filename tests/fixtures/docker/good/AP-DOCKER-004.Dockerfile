FROM ubuntu:22.04

# ok: slopguard.docker.curl-pipe-shell
# Download, verify checksum, then run explicitly
RUN set -eux; \
    curl -fsSL -o /tmp/install.sh https://example.com/install.sh; \
    echo "a1b2c3d4e5f6...  /tmp/install.sh" | sha256sum -c -; \
    chmod +x /tmp/install.sh; \
    /tmp/install.sh; \
    rm /tmp/install.sh

RUN apt-get update && apt-get install -y nodejs
