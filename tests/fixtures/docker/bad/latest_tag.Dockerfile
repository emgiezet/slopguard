# Bad: using latest tag (AP-DOCKER-001 / DL3007)
FROM ubuntu:latest

RUN apt-get update && apt-get install -y curl

COPY . /app
WORKDIR /app
CMD ["./app"]
