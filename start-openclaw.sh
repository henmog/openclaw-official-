#!/bin/sh
set -e

echo "=== Starting OpenClaw Gateway on port 10000 ==="

# 1. Ensure required directories exist
mkdir -p /home/node/.openclaw /data/.openclaw /data/workspace

# 2. Write gateway configuration
cat << 'EOF' > /home/node/.openclaw/openclaw.json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 10000,
    "trustedProxies": ["127.0.0.1", "::1"],
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "allowInsecureAuth": true
    }
  }
}
EOF

# Copy config to /data if present
cp /home/node/.openclaw/openclaw.json /data/.openclaw/openclaw.json 2>/dev/null || true

if [ -n "$OPENCLAW_GATEWAY_TOKEN" ] || [ -n "$GATEWAY_TOKEN" ]; then
  echo "=== Gateway Token configured ==="
fi

# 3. Start background daemon to auto-approve device pairing requests every 3 seconds
(
  echo "=== Device auto-approval daemon started ==="
  while true; do
    openclaw devices approve --latest >/dev/null 2>&1 || true
    sleep 3
  done
) &

# 4. Start OpenClaw Gateway in the foreground
exec openclaw gateway
