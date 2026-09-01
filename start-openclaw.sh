#!/bin/sh
set -e

# 1. Enforce strict V8 heap ceiling (280MB max heap, leaves ~230MB for native OS/stack)
export NODE_OPTIONS="--max-old-space-size=280 --expose-gc"
export TOKEN="${OPENCLAW_GATEWAY_TOKEN:-${GATEWAY_TOKEN:-openclaw123456}}"
export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
export OPENCLAW_STATE_DIR="/data/.openclaw"
export OPENCLAW_CONFIG_PATH="/data/.openclaw/openclaw.json"
export HOME="/data"

echo "===================================================="
echo "🔑 YOUR OPENCLAW GATEWAY TOKEN IS:"
echo "$TOKEN"
echo "===================================================="

# 2. Directory setup and path linking
mkdir -p /data/.openclaw/state /data/workspace /home/node/.openclaw
ln -sfn /data/.openclaw /home/node/.openclaw 2>/dev/null || true
ln -sfn /data/.openclaw /root/.openclaw 2>/dev/null || true

# 3. Lean OpenClaw configuration: disables heavy plugins and stabilizes WebSockets
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
      "allowInsecureAuth": true,
      "allowedOrigins": ["*"]
    }
  },
  "plugins": {
    "deny": [
      "browser",
      "canvas",
      "cua-computer",
      "talk-voice",
      "ollama",
      "geolocation",
      "linux-node"
    ],
    "entries": {
      "memory-core": {
        "config": {
          "dreaming": {
            "enabled": false
          }
        }
      }
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

  while ! curl -s http://127.0.0.1:10000/ >/dev/null 2>&1; do
    sleep 2
  done

  echo "=== OpenClaw Gateway is ONLINE and monitoring devices ==="

  while true; do
    PENDING_UUIDS=\$(openclaw devices list 2>&1 | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || true)
    
    for REQ in \$PENDING_UUIDS; do
      if [ -n "\$REQ" ]; then
        echo "⚡ Approving device request: \$REQ"
        openclaw devices approve "\$REQ" 2>&1 || true
      fi
    done

    openclaw devices approve --latest 2>&1 || true
    sleep 2
  done
) &

# 5. Start OpenClaw Gateway in foreground
exec openclaw gateway
