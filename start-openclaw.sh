#!/bin/sh
set -e

# 1. Set Token and Environment Variables
export TOKEN="${OPENCLAW_GATEWAY_TOKEN:-${GATEWAY_TOKEN:-openclaw123456}}"
export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
export OPENCLAW_CONFIG_PATH="/home/node/.openclaw/openclaw.json"

echo "===================================================="
echo "🔑 YOUR OPENCLAW GATEWAY TOKEN IS:"
echo "$TOKEN"
echo "===================================================="

# 2. Ensure required directories exist
mkdir -p /home/node/.openclaw /data/.openclaw /data/workspace

# 3. Write gateway configuration with mode: "token"
cat << EOF > /home/node/.openclaw/openclaw.json
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 10000,
    "auth": {
      "mode": "token",
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

# 4. Background daemon to auto-approve device pairing requests
(
  echo "=== Device auto-approval daemon started ==="
  sleep 20

  echo "=================================================================="
  echo "🔗 DIRECT DASHBOARD LINK:"
  openclaw dashboard --no-open 2>&1 || true
  echo "=================================================================="

  while true; do
    openclaw devices approve --latest --url ws://127.0.0.1:10000 --token "$TOKEN" >/dev/null 2>&1 || true
    openclaw devices approve --latest --token "$TOKEN" >/dev/null 2>&1 || true
    sleep 3
  done
) &

# 5. Start OpenClaw Gateway in foreground
exec openclaw gateway
