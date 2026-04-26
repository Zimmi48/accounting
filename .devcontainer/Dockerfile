FROM mcr.microsoft.com/devcontainers/javascript-node:24
RUN sudo apt-get update \
    && sudo apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        xdg-utils \
    && sudo rm -rf /var/lib/apt/lists/*