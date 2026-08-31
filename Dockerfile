FROM node:22-bookworm-slim

# Set environment variables
ENV NODE_ENV=production \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NODE_OPTIONS="--max-old-space-size=2048" \
    OPENCLAW_STATE_DIR=/data/.openclaw \
    OPENCLAW_WORKSPACE_DIR=/data/workspace \
    PORT=10000

# Install required system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally via npm
RUN npm install -g openclaw@latest

# Prepare persistent data and config directories
RUN mkdir -p /data/.openclaw /data/workspace /home/node/.openclaw \
    && chown -R node:node /data /home/node

# Copy startup script
COPY start-openclaw.sh /usr/local/bin/start-openclaw.sh
RUN chmod +x /usr/local/bin/start-openclaw.sh

# Expose Render service port
EXPOSE 10000

# Run with tini to handle signals and zombie processes properly
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD sh -c "(while true; do openclaw devices approve --latest >/dev/null 2>&1 || true; sleep 3; done) & exec openclaw gateway start"
