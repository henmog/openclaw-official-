#!/bin/sh
set -e

# Use your Render environment token, or default to 'openclaw123456'
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-${GATEWAY_TOKEN:-openclaw123456}}"

echo "===================================================="
echo "🔑 YOUR OPENCLAW GATEWAY TOKEN IS:"
echo "$TOKEN"
echo "===================================================="

# 1. Ensure required directories exist
mkdir -p /home/node/.openclaw /data/.openclaw /data/workspace

# 2. Write gateway configuration with explicit token authentication
cat << EOF > /home/node/.openclaw/openclaw.json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 10000,
    "auth": {
      "token": "$TOKEN"
    },
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
