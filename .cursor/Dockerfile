FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg sudo unzip openjdk-21-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# Node 24 + pnpm (via corepack) + EAS CLI
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && npm install -g eas-cli

# flyctl for server deploys
RUN curl -fsSL https://fly.io/install.sh | FLYCTL_INSTALL=/usr/local sh

# System libraries Chromium needs for Playwright screenshots
RUN npx -y playwright@latest install-deps chromium && rm -rf /var/lib/apt/lists/*

# Cloud agents run as a non-root ubuntu user with passwordless sudo
RUN id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu \
    && usermod -aG sudo ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
