#!/bin/sh
set -e

# 1. Set Token and Environment Variables
export TOKEN="${OPENCLAW_GATEWAY_TOKEN:-${GATEWAY_TOKEN:-openclaw123456}}"
export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
export OPENCLAW_STATE_DIR="/data/.openclaw"
export OPENCLAW_CONFIG_PATH="/data/.openclaw/openclaw.json"
export HOME="/data"

echo "===================================================="
echo "🔑 YOUR OPENCLAW GATEWAY TOKEN IS:"
echo "$TOKEN"
echo "===================================================="

# 2. Ensure all directories exist and link them so Gateway and CLI share the same SQLite database
mkdir -p /data/.openclaw/state /data/workspace /home/node/.openclaw
ln -sfn /data/.openclaw /home/node/.openclaw 2>/dev/null || true
ln -sfn /data/.openclaw /root/.openclaw 2>/dev/null || true

# 3. Write gateway configuration to the unified path
cat << EOF > /data/.openclaw/openclaw.json
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

# Copy config to /home/node as backup
cp /data/.openclaw/openclaw.json /home/node/.openclaw/openclaw.json 2>/dev/null || true
chmod -R 777 /data /home/node 2>/dev/null || true

# 4. Background daemon: monitors pending UUIDs and approves them automatically
(
  set +e
  echo "=== Device auto-approval daemon started ==="
  echo "Waiting for OpenClaw Gateway to become ready..."

  # Wait until the gateway HTTP server is active
  while ! curl -s http://127.0.0.1:10000/ >/dev/null 2>&1; do
    sleep 2
  done

  echo "=== OpenClaw Gateway is ONLINE and monitoring devices ==="

  while true; do
    # Extract any pending UUID request IDs from devices list
    PENDING_UUIDS=$(openclaw devices list 2>&1 | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
    
    for REQ in $PENDING_UUIDS; do
      if [ -n "$REQ" ]; then
        echo "⚡ Approving device request: $REQ"
        openclaw devices approve "$REQ" 2>&1 || true
      fi
    done

    # Fallback to approve latest
    openclaw devices approve --latest 2>&1 || true
    sleep 2
  done
) &

# 5. Start OpenClaw Gateway in foreground
exec openclaw gateway
