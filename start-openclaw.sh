#!/bin/bash
set -e

# 1. Enforce strict V8 heap ceiling (280MB max heap, leaves ~230MB for native OS/stack)
export NODE_OPTIONS="--max-old-space-size=280 --expose-gc"
export TOKEN="${OPENCLAW_GATEWAY_TOKEN:-${GATEWAY_TOKEN:-openclaw123456}}"
export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
export OPENCLAW_STATE_DIR="/data/.openclaw"
export OPENCLAW_CONFIG_PATH="/data/.openclaw/openclaw.json"
export HOME="/data"
export NVIDIA_KEY="${NVIDIA_API_KEY:-${OPENAI_API_KEY:-nvapi-key}}"

echo "===================================================="
echo "🔑 YOUR OPENCLAW GATEWAY TOKEN IS:"
echo "$TOKEN"
echo "===================================================="

# 2. Directory setup and path linking
mkdir -p /data/.openclaw/state /data/workspace /home/node/.openclaw
ln -sfn /data/.openclaw /home/node/.openclaw 2>/dev/null || true
ln -sfn /data/.openclaw /root/.openclaw 2>/dev/null || true

# 3. Write gateway configuration with your NVIDIA models
cat << JSON_CONFIG > /data/.openclaw/openclaw.json
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
  "agents": {
    "defaults": {
      "model": {
        "primary": "nvidia/nemotron-3-super-120b-a12b",
        "fallbacks": [
          "nvidia/nemotron-3-ultra-550b-a55b"
        ]
      },
      "models": {
        "nvidia/nemotron-3-super-120b-a12b": {
          "alias": "nemotron-super-120b"
        },
        "nvidia/nemotron-3-ultra-550b-a55b": {
          "alias": "nemotron-ultra-550b"
        },
        "meta/muse-glimmer-30b": {
          "alias": "muse-glimmer-30b"
        },
        "nvidia/nemotron-3.5-lightning-30b-a3b": {
          "alias": "nemotron-lightning-30b"
        },
        "deepseek-ai/deepseek-v4-flash-0731": {
          "alias": "deepseek-v4-flash"
        },
        "moonshotai/kimi-k3": {
          "alias": "kimi-k3"
        }
      }
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "nvidia": {
        "baseUrl": "https://integrate.api.nvidia.com/v1",
        "apiKey": "$NVIDIA_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "nvidia/nemotron-3-super-120b-a12b",
            "name": "nvidia/nemotron-3-super-120b-a12b",
            "contextTokens": 131072,
            "maxTokens": 16384
          },
          {
            "id": "nvidia/nemotron-3-ultra-550b-a55b",
            "name": "nvidia/nemotron-3-ultra-550b-a55b",
            "contextTokens": 131072,
            "maxTokens": 16384
          },
          {
            "id": "meta/muse-glimmer-30b",
            "name": "meta/muse-glimmer-30b",
            "contextTokens": 131072,
            "maxTokens": 8192
          },
          {
            "id": "nvidia/nemotron-3.5-lightning-30b-a3b",
            "name": "nvidia/nemotron-3.5-lightning-30b-a3b",
            "contextTokens": 131072,
            "maxTokens": 16384
          },
          {
            "id": "deepseek-ai/deepseek-v4-flash-0731",
            "name": "deepseek-ai/deepseek-v4-flash-0731",
            "contextTokens": 131072,
            "maxTokens": 16384
          },
          {
            "id": "moonshotai/kimi-k3",
            "name": "moonshotai/kimi-k3",
            "contextTokens": 131072,
            "maxTokens": 16384
          }
        ]
      }
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
JSON_CONFIG

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
    PENDING_UUIDS=$(openclaw devices list 2>&1 | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" || true)
    
    for REQ in $PENDING_UUIDS; do
      if [ -n "$REQ" ]; then
        echo "⚡ Approving device request: $REQ"
        openclaw devices approve "$REQ" 2>&1 || true
      fi
    done

    openclaw devices approve --latest 2>&1 || true
    sleep 2
  done
) &

# 5. Start OpenClaw Gateway in foreground
exec openclaw gateway
