#!/bin/bash
set -e

mkdir -p /root/.openclaw/agents/main/sessions
mkdir -p /root/.openclaw/credentials
mkdir -p /root/.openclaw/sessions

# 1. Restore previous state from HF Dataset (if configured)
python3 /app/sync.py restore || true

# Clean up stale locks
rm -rf /root/.openclaw/browser/*/user-data/Singleton* /tmp/org.chromium.Chromium.* 2>/dev/null || true

# 2. Port & Host Detection
PORT="${PORT:-10000}"

# 3. Generate openclaw.json with Device Auth Bypassed
python3 - <<PYEOF
import os, json

config_path = "/root/.openclaw/openclaw.json"

models_raw = [m.strip() for m in os.environ.get("MODEL", "z-ai/glm-5.1").split(",") if m.strip()]
formatted_models = [{"id": m, "name": m, "contextWindow": 128000} for m in models_raw]
primary_id = models_raw[0] if models_raw else "z-ai/glm-5.1"

clean_base = os.environ.get("OPENAI_API_BASE", "https://integrate.api.nvidia.com/v1").replace("/chat/completions", "").strip()
if clean_base.endswith("/v1/"):
    clean_base = clean_base[:-1]

token = os.environ.get("OPENCLAW_GATEWAY_PASSWORD", os.environ.get("OPENCLAW_GATEWAY_TOKEN", ""))
port = int(os.environ.get("PORT", "10000"))

config = {
    "gateway": {
        "mode": "local",
        "bind": "lan",
        "port": port,
        "trustedProxies": ["0.0.0.0/0"],
        "auth": {
            "mode": "token",
            "token": token
        },
        "controlUi": {
            "dangerouslyDisableDeviceAuth": True,
            "allowInsecureAuth": True,
            "allowedOrigins": ["*"],
            "dangerouslyAllowHostHeaderOriginFallback": True
        },
        "nodes": {
            "browser": {
                "mode": "auto"
            }
        }
    },
    "agents": {
        "defaults": {
            "workspace": "/root/.openclaw/workspace",
            "model": {
                "primary": "nvidia/" + primary_id
            }
        },
        "list": [{"id": "main", "name": "Main Agent"}]
    },
    "models": {
        "providers": {
            "nvidia": {
                "apiKey": os.environ.get("OPENAI_API_KEY", ""),
                "baseUrl": clean_base,
                "api": "openai-completions",
                "models": formatted_models
            }
        }
    },
    "tools": {
        "profile": "full",
        "web": {
            "search": {
                "enabled": True,
                "provider": "brave",
                "apiKey": os.environ.get("BRAVE_KEY", ""),
                "maxResults": 5
            },
            "fetch": {"enabled": True}
        }
    },
    "commands": {
        "native": "auto",
        "restart": True
    }
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print(f"Config generated: primary=nvidia/{primary_id}, port={port}")
PYEOF

# 4. Auto-Approve Device Pairing Daemon (Background loop for zero-terminal pairing)
(
while true; do
    openclaw devices list --json 2>/dev/null | python3 -c "
import sys, json, subprocess
try:
    raw = sys.stdin.read().strip()
    if raw:
        data = json.loads(raw)
        devices = data if isinstance(data, list) else data.get('pending', [])
        for d in devices:
            rid = d.get('id') or d.get('requestId')
            if rid:
                subprocess.run(['openclaw', 'devices', 'approve', str(rid)], capture_output=True)
                print(f'Auto-approved device pairing: {rid}')
except Exception:
    pass
" || true
    sleep 5
done
) &

# 5. Scheduled backup daemon (every 10 minutes)
(while true; do sleep 600; python3 /app/sync.py backup; done) &

# 6. Gateway Main Process
while true; do
    echo "Starting OpenClaw Gateway on port $PORT..."
    openclaw gateway run --port "$PORT" --token "$OPENCLAW_GATEWAY_PASSWORD" --allow-unconfigured &
    GATEWAY_PID=$!
    wait $GATEWAY_PID
    echo "Gateway stopped. Backing up data..."
    python3 /app/sync.py backup --force || true
    sleep 3
done
