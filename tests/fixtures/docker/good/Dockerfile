FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --no-log-init --create-home app
USER app

WORKDIR /home/app

COPY --chown=app:app . .

CMD ["./app"]
