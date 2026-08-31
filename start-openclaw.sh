#!/bin/sh
set -e

# 1. Set Token and Paths
export TOKEN="${OPENCLAW_GATEWAY_TOKEN:-${GATEWAY_TOKEN:-openclaw123456}}"
export OPENCLAW_CONFIG_PATH="/home/node/.openclaw/openclaw.json"
export OPENCLAW_GATEWAY_TOKEN="$TOKEN"

echo "===================================================="
echo "🔑 YOUR OPENCLAW GATEWAY TOKEN IS:"
echo "$TOKEN"
echo "===================================================="

# 2. Ensure required directories exist
mkdir -p /home/node/.openclaw /data/.openclaw /data/workspace

# 3. Write gateway configuration
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

# 4. Background daemon to auto-approve devices with the required token & url
(
  echo "=== Device auto-approval daemon started ==="
  # Wait for Gateway to initialize
  sleep 15

  # Print a direct 1-click owner pairing URL in the Render logs
  echo "=================================================================="
  echo "🔗 DIRECT 1-CLICK DASHBOARD PAIRING LINK:"
  openclaw dashboard --no-open --token "$TOKEN" 2>&1 || true
  echo "=================================================================="

  # Auto-approve incoming browser connections continuously
  while true; do
    openclaw devices approve --latest --url ws://127.0.0.1:10000 --token "$TOKEN" >/dev/null 2>&1 || true
    openclaw devices approve --latest --token "$TOKEN" >/dev/null 2>&1 || true
    sleep 3
  done
) &

# 5. Start OpenClaw Gateway
exec openclaw gateway
