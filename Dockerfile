# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=node:24.15.0-bookworm-slim
ARG OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:2026.7.1-2@sha256:8789721d2e9b24b780a1504b56deb4c6bd5c7dbf96a1dd117e7c45c2ed72c8ac

FROM ${NODE_IMAGE} AS plugin-builder

ARG PNPM_VERSION=11.9.0

RUN corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate

WORKDIR /build/ag-plugin-openclaw

COPY ag-plugin-openclaw/package.json ag-plugin-openclaw/pnpm-lock.yaml ag-plugin-openclaw/pnpm-workspace.yaml ./
COPY ag-plugin-openclaw/tsconfig.json ag-plugin-openclaw/tsconfig.build.json ./
COPY ag-plugin-openclaw/openclaw.plugin.json ag-plugin-openclaw/README.md ./

RUN pnpm install --frozen-lockfile

COPY ag-plugin-openclaw/src ./src

RUN pnpm build \
    && pnpm pack --pack-destination /opt/plugin-package

FROM ${OPENCLAW_IMAGE}

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/*

COPY --from=plugin-builder \
    /opt/plugin-package/agpay-openclaw-plugin-*.tgz \
    /opt/agpay-plugin/agpay-openclaw-plugin.tgz
COPY ag-openclaw-playground/scripts/openclaw-playground.sh \
    /usr/local/bin/openclaw-playground

RUN chmod 0755 /usr/local/bin/openclaw-playground \
    && mkdir -p \
      /home/node/.openclaw/secrets \
      /home/node/.openclaw/workspace \
      /home/node/.config/openclaw \
    && chown -R node:node \
      /home/node/.openclaw \
      /home/node/.config/openclaw \
      /opt/agpay-plugin

USER node
WORKDIR /app

EXPOSE 18789
