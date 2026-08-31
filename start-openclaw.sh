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

# 3. Write gateway configuration
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

# 4. Background daemon that waits for gateway readiness and auto-approves devices
(
  set +e
  echo "=== Device auto-approval daemon started ==="
  echo "Waiting for OpenClaw Gateway to listen on port 10000..."

  # Wait until the gateway HTTP server is actually responding
  while ! curl -s http://127.0.0.1:10000/ >/dev/null 2>&1; do
    sleep 2
  done

  echo "=== OpenClaw Gateway is ONLINE ==="
  sleep 2

  # Output the direct pairing URL to Render logs
  echo "=================================================================="
  echo "🔗 DIRECT DASHBOARD PAIRING LINK (ONE-CLICK LOGIN):"
  openclaw dashboard --no-open 2>&1 || true
  echo "=================================================================="

  # Continuous loop to approve every pending device ID
  while true; do
    PENDING_IDS=$(openclaw devices list --json 2>/dev/null | jq -r '(.pending[]?.requestId // empty, .requests[]?.id // empty, .[]?.requestId // empty)' 2>/dev/null || true)
    for ID in $PENDING_IDS; do
      if [ -n "$ID" ] && [ "$ID" != "null" ]; then
        echo "Approving device request ID: $ID"
        openclaw devices approve "$ID" 2>&1 || true
      fi
    done

    # Fallback to approve latest
    openclaw devices approve --latest 2>/dev/null || true
    sleep 3
  done
) &

# 5. Start OpenClaw Gateway in foreground
exec openclaw gateway
