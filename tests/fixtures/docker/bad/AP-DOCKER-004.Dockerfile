FROM ubuntu:22.04

# ruleid: slopguard.docker.curl-pipe-shell
RUN curl -fsSL https://example.com/install.sh | bash

# ruleid: slopguard.docker.curl-pipe-shell
RUN wget -qO- https://example.com/setup.py | python3

RUN apt-get update && apt-get install -y nodejs
