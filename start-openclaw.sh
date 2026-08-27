#!/bin/bash
set -e

PORT=${PORT:-10000}
GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-"openclaw-admin-token"}
CONFIG_DIR="/data/.openclaw"

mkdir -p "$CONFIG_DIR" "/data/workspace" "/home/node/.openclaw"

# Generate or update openclaw.json with allowedOrigins, trustedProxies, and auth token
cat <<EOF > "$CONFIG_DIR/openclaw.json"
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": $PORT,
    "trustedProxies": [
      "127.0.0.1",
      "::1",
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16"
    ],
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "controlUi": {
      "enabled": true,
      "allowedOrigins": [
        "https://openclaw-official.onrender.com",
        "https://*.onrender.com",
        "http://localhost:$PORT",
        "http://127.0.0.1:$PORT",
        "*"
      ],
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowInsecureAuth": true
    }
  }
}
EOF

# Ensure the node user directory shares the same config
cp "$CONFIG_DIR/openclaw.json" /home/node/.openclaw/openclaw.json 2>/dev/null || true
chown -R node:node /data /home/node 2>/dev/null || true

echo "=== Starting OpenClaw Gateway on port $PORT ==="
echo "=== Gateway Token configured ==="

exec openclaw gateway run --port "$PORT" --bind lan
