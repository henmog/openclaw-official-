# Opt-in plugin dependencies and supported runtime builds (space- or comma-separated ids).
ARG OPENCLAW_EXTENSIONS=""
ARG OPENCLAW_BUNDLED_PLUGIN_DIR=extensions
ARG OPENCLAW_DOCKER_BUILD_NODE_OPTIONS="--max-old-space-size=8192"
ARG OPENCLAW_DOCKER_BUILD_TSDOWN_MAX_OLD_SPACE_MB="4096"
ARG OPENCLAW_DOCKER_BUILD_SKIP_DTS=1
ARG OPENCLAW_NODE_BOOKWORM_IMAGE="docker.io/library/node:24-bookworm@sha256:934240a162082fd8b8a2f90cd5114446443f1eba1c5378f6687167ca405e6584"
ARG OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE="docker.io/library/node:24-bookworm-slim@sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03"
ARG OPENCLAW_NODE_BOOKWORM_SLIM_DIGEST="sha256:3638d9a6fe4030bd716be989438248074489337ba3275657f93595428be4fc03"
ARG OPENCLAW_BUN_IMAGE="docker.io/oven/bun:1.3.14@sha256:e10577f0db68676a7024391c6e5cb4b879ebd17188ab750cf10024a6d700e5c4"

FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS workspace-deps
ARG OPENCLAW_EXTENSIONS
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
COPY scripts/lib/docker-plugin-selection.mjs /tmp/docker-plugin-selection.mjs
COPY scripts/lib/root-package-bundled-plugin-excludes.mjs /tmp/root-package-bundled-plugin-excludes.mjs
COPY package.json /tmp/package.json
COPY packages /tmp/packages
COPY ${OPENCLAW_BUNDLED_PLUGIN_DIR} /tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}
RUN mkdir -p /out/packages "/out/${OPENCLAW_BUNDLED_PLUGIN_DIR}" && \
    for manifest in /tmp/packages/*/package.json; do \
      [ -f "$manifest" ] || continue; \
      pkg_dir="${manifest%/package.json}"; \
      pkg_name="${pkg_dir##*/}"; \
      mkdir -p "/out/packages/$pkg_name" && \
      cp "$manifest" "/out/packages/$pkg_name/package.json"; \
    done && \
    node /tmp/docker-plugin-selection.mjs "/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}" "$OPENCLAW_EXTENSIONS" \
      > /out/openclaw-selected-plugin-dirs && \
    node /tmp/docker-plugin-selection.mjs "/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}" "$OPENCLAW_EXTENSIONS" \
      --required-platform-packages > /out/openclaw-required-platform-packages && \
    node /tmp/docker-plugin-selection.mjs "/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}" "$OPENCLAW_EXTENSIONS" \
      --required-bundled /tmp/package.json > /tmp/openclaw-workspace-plugin-dirs && \
    while IFS= read -r ext; do \
      ext_dir="/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}/$ext"; \
      if [ -f "$ext_dir/package.json" ]; then \
        mkdir -p "/out/${OPENCLAW_BUNDLED_PLUGIN_DIR}/$ext" && \
        cp "$ext_dir/package.json" "/out/${OPENCLAW_BUNDLED_PLUGIN_DIR}/$ext/package.json"; \
      fi; \
    done < /tmp/openclaw-workspace-plugin-dirs

# ── Stage 2: Build ──────────────────────────────────────────────
FROM ${OPENCLAW_BUN_IMAGE} AS bun-binary
FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
ARG OPENCLAW_DOCKER_BUILD_NODE_OPTIONS
ARG OPENCLAW_DOCKER_BUILD_TSDOWN_MAX_OLD_SPACE_MB
ARG OPENCLAW_DOCKER_BUILD_SKIP_DTS

COPY --from=bun-binary /usr/local/bin/bun /usr/local/bin/bun
RUN corepack enable

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY node-version.mjs ./
COPY openclaw.mjs ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts/postinstall-bundled-plugins.mjs scripts/preinstall-package-manager-warning.mjs scripts/windows-cmd-helpers.mjs scripts/prepare-git-hooks.mjs ./scripts/
COPY scripts/lib/guard-inventory-utils.mjs ./scripts/lib/guard-inventory-utils.mjs
COPY scripts/lib/package-dist-imports.mjs ./scripts/lib/package-dist-imports.mjs

COPY --from=workspace-deps /out/packages/ ./packages/
COPY --from=workspace-deps /out/${OPENCLAW_BUNDLED_PLUGIN_DIR}/ ./${OPENCLAW_BUNDLED_PLUGIN_DIR}/
COPY --from=workspace-deps /out/openclaw-selected-plugin-dirs /tmp/openclaw-selected-plugin-dirs
COPY --from=workspace-deps /out/openclaw-required-platform-packages /tmp/openclaw-required-platform-packages

RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile \
      --config.supportedArchitectures.os=linux \
      --config.supportedArchitectures.cpu="$(node -p 'process.arch')" \
      --config.supportedArchitectures.libc=glibc

RUN set -eux; \
    if ! grep -qx 'matrix' /tmp/openclaw-selected-plugin-dirs; then \
      echo "==> matrix not bundled, skipping matrix-sdk-crypto check"; \
      exit 0; \
    fi; \
    echo "==> Verifying critical native addons..."; \
    for attempt in 1 2 3 4 5; do \
      if find /app/node_modules -name "matrix-sdk-crypto*.node" 2>/dev/null | grep -q .; then \
        exit 0; \
      fi; \
      echo "matrix-sdk-crypto native addon missing; retrying download (${attempt}/5)"; \
      node /app/node_modules/@matrix-org/matrix-sdk-crypto-nodejs/download-lib.js || true; \
      sleep $((attempt * 2)); \
    done; \
    find /app/node_modules -name "matrix-sdk-crypto*.node" 2>/dev/null | grep -q . || \
      (echo "ERROR: matrix-sdk-crypto native addon missing after retries" >&2 && exit 1)

ARG GIT_COMMIT=""
ARG OPENCLAW_BUILD_TIMESTAMP=""
ENV GIT_COMMIT=${GIT_COMMIT} \
    OPENCLAW_BUILD_TIMESTAMP=${OPENCLAW_BUILD_TIMESTAMP}

COPY . .

RUN find /app -path /app/node_modules -prune -o -exec chmod a+rX {} +

RUN for dir in /app/${OPENCLAW_BUNDLED_PLUGIN_DIR} /app/.agent /app/.agents; do \
      if [ -d "$dir" ]; then \
        find "$dir" -type d -exec chmod 755 {} +; \
        find "$dir" -type f -exec chmod 644 {} +; \
      fi; \
    done

RUN pnpm_config_verify_deps_before_run=false pnpm canvas:a2ui:bundle || \
    (echo "A2UI bundle: creating stub (non-fatal)" && \
     mkdir -p extensions/canvas/src/host/a2ui && \
     echo "/* A2UI bundle unavailable in this build */" > extensions/canvas/src/host/a2ui/a2ui.bundle.js && \
     echo "stub" > extensions/canvas/src/host/a2ui/.bundle.hash && \
     rm -rf vendor/a2ui apps/shared/OpenClawKit/Tools/CanvasA2UI)

ENV OPENCLAW_PREFER_PNPM=1
ENV OPENCLAW_DOCKER_BUILD_TSDOWN_MAX_OLD_SPACE_MB=4096
ENV OPENCLAW_TSDOWN_MAX_OLD_SPACE_MB=4096

RUN set -eu; \
    selected_plugin_dirs="$(cat /tmp/openclaw-selected-plugin-dirs)"; \
    if [ -z "$OPENCLAW_BUILD_TIMESTAMP" ]; then \
      OPENCLAW_BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
      export OPENCLAW_BUILD_TIMESTAMP; \
    fi; \
    if grep -qx 'qa-lab' /tmp/openclaw-selected-plugin-dirs; then \
      export OPENCLAW_BUILD_PRIVATE_QA=1 OPENCLAW_ENABLE_PRIVATE_QA_CLI=1; \
    fi; \
    OPENCLAW_INTERNAL_DOCKER_BUILD_PLUGIN_IDS="$selected_plugin_dirs" OPENCLAW_RUN_NODE_SKIP_DTS_BUILD="$OPENCLAW_DOCKER_BUILD_SKIP_DTS" OPENCLAW_TSDOWN_MAX_OLD_SPACE_MB="$OPENCLAW_DOCKER_BUILD_TSDOWN_MAX_OLD_SPACE_MB" NODE_OPTIONS="$OPENCLAW_DOCKER_BUILD_NODE_OPTIONS" pnpm_config_verify_deps_before_run=false pnpm build:docker; \
    pnpm_config_verify_deps_before_run=false pnpm ui:build

RUN if grep -qx 'qa-lab' /tmp/openclaw-selected-plugin-dirs; then \
      pnpm_config_verify_deps_before_run=false pnpm qa:lab:build && \
      mkdir -p dist/extensions/qa-lab/web && \
      rm -rf dist/extensions/qa-lab/web/dist && \
      cp -R extensions/qa-lab/web/dist dist/extensions/qa-lab/web/dist; \
    fi

# ── Stage: Runtime Assets ───────────────────────────────────────
FROM build AS runtime-assets
ARG OPENCLAW_BUNDLED_PLUGIN_DIR

RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    node scripts/list-prod-store-packages.mjs | xargs -r pnpm store add && \
    CI=true pnpm prune --prod \
      --config.offline=true \
      --config.supportedArchitectures.os=linux \
      --config.supportedArchitectures.cpu="$(node -p 'process.arch')" \
      --config.supportedArchitectures.libc=glibc && \
    OPENCLAW_EXTENSIONS="$(cat /tmp/openclaw-selected-plugin-dirs)" OPENCLAW_BUNDLED_PLUGIN_DIR="$OPENCLAW_BUNDLED_PLUGIN_DIR" node scripts/prune-docker-plugin-dist.mjs && \
    node scripts/postinstall-bundled-plugins.mjs && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete && \
    if [ -L /app/node_modules/@openclaw/ai ]; then \
      ai_runtime_target="$(readlink -f /app/node_modules/@openclaw/ai)" && \
      ai_runtime_tmp="$(mktemp -d)" && \
      cp -a "$ai_runtime_target" "$ai_runtime_tmp/ai" && \
      rm /app/node_modules/@openclaw/ai && \
      mv "$ai_runtime_tmp/ai" /app/node_modules/@openclaw/ai && \
      rmdir "$ai_runtime_tmp"; \
    fi && \
    rm -rf \
      /app/node_modules/openclaw \
      /app/node_modules/.bin/openclaw \
      /app/node_modules/.pnpm/openclaw@*/node_modules/openclaw && \
    if ! grep -q '^@anthropic-ai/claude-agent-sdk-' /tmp/openclaw-required-platform-packages; then \
      find /app/node_modules/@anthropic-ai -maxdepth 1 -type d \
        -name 'claude-agent-sdk-linux-*' -exec rm -rf {} +; \
    fi && \
    node --input-type=module -e 'await import("grammy")' && \
    node scripts/check-package-dist-imports.mjs /app

# ── Runtime base image ──────────────────────────────────────────
FROM ${OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE} AS base-runtime
ARG OPENCLAW_NODE_BOOKWORM_SLIM_DIGEST
LABEL org.opencontainers.image.base.name="docker.io/library/node:24-bookworm-slim" \
  org.opencontainers.image.base.digest="${OPENCLAW_NODE_BOOKWORM_SLIM_DIGEST}"

# ── Stage 3: Runtime ────────────────────────────────────────────
FROM base-runtime
ARG OPENCLAW_BUNDLED_PLUGIN_DIR

WORKDIR /app

RUN --mount=type=cache,id=openclaw-bookworm-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=openclaw-bookworm-apt-lists,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git hostname lsof openssl procps python3 tini && \
    update-ca-certificates

RUN npm install --global npm@latest && \
    npm_dir="$(npm root --global)/npm" && \
    cp "$npm_dir/package.json" /tmp/npm-package.json && \
    node -e 'const fs = require("node:fs"); const file = process.argv; const packageJson = JSON.parse(fs.readFileSync(file, "utf8")); delete packageJson.devDependencies; fs.writeFileSync(file, `${JSON.stringify(packageJson, null, 2)}\n`);' "$npm_dir/package.json" && \
    npm update --prefix "$npm_dir" --omit=dev --ignore-scripts --no-audit --no-fund && \
    mv /tmp/npm-package.json "$npm_dir/package.json" && \
    npm cache clean --force

RUN chown node:node /app

COPY --from=runtime-assets --chown=node:node /app/dist ./dist
COPY --from=runtime-assets --chown=node:node /app/node_modules ./node_modules
COPY --from=runtime-assets --chown=node:node /app/package.json .
COPY --from=runtime-assets --chown=node:node /app/pnpm-workspace.yaml .
COPY --from=runtime-assets --chown=node:node /app/patches ./patches
COPY --from=runtime-assets --chown=node:node /app/node-version.mjs .
COPY --from=runtime-assets --chown=node:node /app/openclaw.mjs .
COPY --from=runtime-assets --chown=node:node /app/src/agents/templates ./src/agents/templates
COPY --from=runtime-assets --chown=node:node /app/${OPENCLAW_BUNDLED_PLUGIN_DIR} ./${OPENCLAW_BUNDLED_PLUGIN_DIR}
COPY --from=runtime-assets --chown=node:node /app/skills ./skills
COPY --from=runtime-assets --chown=node:node /app/docs ./docs
COPY --from=runtime-assets --chown=node:node /app/qa ./qa

ENV COREPACK_HOME=/usr/local/share/corepack
RUN install -d -m 0755 "$COREPACK_HOME" && \
    corepack enable && \
    for attempt in 1 2 3 4 5; do \
      if corepack prepare "$(node -p "require('./package.json').packageManager")" --activate; then \
        break; \
      fi; \
      if [ "$attempt" -eq 5 ]; then \
        exit 1; \
      fi; \
      sleep $((attempt * 2)); \
    done && \
    chmod -R a+rX "$COREPACK_HOME"

ARG OPENCLAW_IMAGE_APT_PACKAGES
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
ENV PATH="/home/node/.local/bin:${PATH}"
RUN --mount=type=cache,id=openclaw-bookworm-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=openclaw-bookworm-apt-lists,target=/var/lib/apt,sharing=locked \
    packages="${OPENCLAW_IMAGE_APT_PACKAGES:-$OPENCLAW_DOCKER_APT_PACKAGES}"; \
    if [ -n "$packages" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $packages; \
    fi

RUN ln -sf /app/openclaw.mjs /usr/local/bin/openclaw \
 && chmod 755 /app/openclaw.mjs

# Pre-create directory and default config with trusted proxies
RUN install -d -m 0755 -o node -g node /home/node/.config && \
    install -d -m 0700 -o node -g node \
      /home/node/.openclaw \
      /home/node/.openclaw/workspace \
      /home/node/.config/openclaw && \
    echo '{"gateway":{"mode":"local","bind":"lan","port":10000,"trustedProxies":["127.0.0.1","::1"],"controlUi":{"dangerouslyAllowHostHeaderOriginFallback":true}}}' > /home/node/.openclaw/openclaw.json && \
    chown -R node:node /home/node/.openclaw /home/node/.config

# Create auto-approval daemon entrypoint script
RUN echo '#!/bin/sh' > /app/docker-entrypoint.sh && \
    echo '(while true; do node /app/openclaw.mjs devices approve --latest >/dev/null 2>&1 || true; sleep 2; done) &' >> /app/docker-entrypoint.sh && \
    echo 'exec node /app/openclaw.mjs gateway run "$@"' >> /app/docker-entrypoint.sh && \
    chmod +x /app/docker-entrypoint.sh && \
    chown node:node /app/docker-entrypoint.sh

ENV NODE_ENV=production

USER node

HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD ["node", "dist/docker-healthcheck.js"]
ENTRYPOINT ["tini", "-s", "--"]
CMD ["/app/docker-entrypoint.sh"]
