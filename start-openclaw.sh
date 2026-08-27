#!/usr/bin/env bash
set -e

# Default port to Render PORT or fallback to 10000
PORT="${PORT:-${OPENCLAW_GATEWAY_PORT:-10000}}"
STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"

echo "=== Starting OpenClaw Gateway on port ${PORT} ==="

# Ensure directories exist
mkdir -p "${STATE_DIR}" "${WORKSPACE_DIR}"

# Generate openclaw.json if not present or configure network bindings
CONFIG_FILE="${STATE_DIR}/openclaw.json"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "Creating initial gateway configuration at ${CONFIG_FILE}..."
  cat <<EOF > "${CONFIG_FILE}"
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": ${PORT},
    "trustedProxies": [
      "127.0.0.1",
      "::1",
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16"
    ],
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": [
        "*"
      ]
    }
  }
}
EOF
fi

# Ensure user node owns the persistent state directory if running as root
if [ "$(id -u)" = "0" ]; then
  chown -R node:node /data /home/node 2>/dev/null || true
  exec su node -c "openclaw gateway --allow-unconfigured --port ${PORT} --bind lan"
else
  exec openclaw gateway --allow-unconfigured --port "${PORT}" --bind lan
fi
