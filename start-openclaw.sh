#!/bin/bash
set -e

mkdir -p /root/.openclaw/agents/main/sessions
mkdir -p /root/.openclaw/credentials
mkdir -p /root/.openclaw/sessions
mkdir -p /root/.openclaw/workspace

# 1. Restore previous backup from Hugging Face Dataset (if configured)
python3 /app/sync.py restore || true

# 2. Generate clean, proxy-safe and auto-pairing configuration
python3 - <<PYEOF
import os, json

config_path = "/root/.openclaw/openclaw.json"

models_raw = [m.strip() for m in os.environ.get("MODEL", "openai/gpt-oss-120b").split(",") if m.strip()]
formatted_models = [{"id": m, "name": m, "contextWindow": 128000} for m in models_raw]
primary_id = models_raw[0] if models_raw else "openai/gpt-oss-120b"

clean_base = os.environ.get("OPENAI_API_BASE", "https://integrate.api.nvidia.com/v1").replace("/chat/completions", "").strip()
gateway_pass = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "") or os.environ.get("OPENCLAW_GATEWAY_PASSWORD", "")

port = int(os.environ.get("PORT", 10000))

config = {
    "gateway": {
        "mode": "local",
        "bind": "lan",
        "port": port,
        "trustedProxies": ["0.0.0.0/0", "127.0.0.1", "10.0.0.0/8", "172.16.0.0/12"],
        "auth": {
            "mode": "token",
            "token": gateway_pass
        },
        "controlUi": {
            "allowInsecureAuth": True,
            "dangerouslyDisableDeviceAuth": True,
            "allowedOrigins": ["*"],
            "dangerouslyAllowHostHeaderOriginFallback": True
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
                "baseUrl": clean_base,
                "apiKey": os.environ.get("OPENAI_API_KEY", ""),
                "api": "openai-completions",
                "models": formatted_models
            }
        }
    },
    "commands": {"restart": True}
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("OpenClaw configuration generated successfully.")
PYEOF

# 3. Background device auto-approval loop (Approves any browser connect automatically)
(
while true; do
    openclaw devices list --json 2>/dev/null | python3 -c "
import sys, json, subprocess
try:
    data = json.load(sys.stdin)
    devices = data if isinstance(data, list) else data.get('pending', [])
    for d in devices:
        rid = d.get('id') or d.get('requestId')
        if rid:
            subprocess.run(['openclaw', 'devices', 'approve', rid])
            print('Auto-approved device: ' + str(rid))
except Exception:
    pass
" || true
    sleep 3
done
) &

# 4. Periodic backup to Hugging Face (every 10 minutes)
(while true; do sleep 600; python3 /app/sync.py backup; done) &

# 5. Start the Gateway
while true; do
    echo "Starting OpenClaw gateway on port $PORT..."
    openclaw gateway run --port "$PORT" --allow-unconfigured &
    GATEWAY_PID=$!
    wait $GATEWAY_PID
    echo "Gateway stopped. Backing up data..."
    python3 /app/sync.py backup --force || true
    sleep 3
done
