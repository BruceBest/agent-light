#!/bin/bash
# Hermes Traffic Light — One-shot setup
# Flash firmware, install hooks, configure Hermes shell hooks.
#
# Usage:
#   bash setup.sh                # local mode (light on this machine)
#   bash setup.sh --remote       # remote mode (light on another machine via Tailscale/LAN)
#   bash setup.sh --remote --light-host 100.x.x.x --light-port 9090
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USER_HOME="$HOME"
HERMES_DIR="$USER_HOME/.hermes"
AGENT_HOOKS="$HERMES_DIR/agent-hooks"
CONFIG="$HERMES_DIR/config.yaml"
ALLOWLIST="$HERMES_DIR/shell-hooks-allowlist.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }

# Parse arguments
MODE="local"
LIGHT_HOST="100.64.0.1"
LIGHT_PORT="9090"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote) MODE="remote"; shift ;;
        --light-host) LIGHT_HOST="$2"; shift 2 ;;
        --light-port) LIGHT_PORT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo "╔══════════════════════════════════════╗"
echo "║    Hermes Traffic Light — Setup      ║"
echo "╠══════════════════════════════════════╣"
if [ "$MODE" = "remote" ]; then
echo "║  Mode: REMOTE (via Tailscale/LAN)    ║"
echo "║  Light at: ${LIGHT_HOST}:${LIGHT_PORT}          "
else
echo "║  Mode: LOCAL (USB serial)            ║"
fi
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Check prerequisites ──────────────────────────────────────────

echo "▸ Checking prerequisites..."

# curl (needed for remote mode)
if [ "$MODE" = "remote" ]; then
    if command -v curl &>/dev/null; then
        ok "curl found"
    else
        fail "curl not found. Install: sudo apt install curl"
        exit 1
    fi
fi

# Python serial (needed for local mode)
if [ "$MODE" = "local" ]; then
    if python3 -c "import serial" 2>/dev/null; then
        ok "pyserial installed"
    else
        echo "  Installing pyserial..."
        pip3 install pyserial
        ok "pyserial installed"
    fi

    # Arduino CLI
    if command -v arduino-cli &>/dev/null || [ -x "$USER_HOME/.local/bin/arduino-cli" ]; then
        ARDUINO_CLI="${ARDUINO_CLI:-$(command -v arduino-cli || echo "$USER_HOME/.local/bin/arduino-cli")}"
        ok "arduino-cli found: $ARDUINO_CLI"
    else
        fail "arduino-cli not found. Install:"
        echo "  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR=~/.local/bin sh"
        exit 1
    fi

    # ESP32 platform
    if "$ARDUINO_CLI" core list 2>/dev/null | grep -q "esp32:esp32"; then
        ok "esp32 platform installed"
    else
        echo "  Installing esp32 platform..."
        "$ARDUINO_CLI" core update-index
        "$ARDUINO_CLI" core install esp32:esp32
        ok "esp32 platform installed"
    fi

    # Serial port
    PORT=$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -1)
    if [ -n "$PORT" ]; then
        ok "Serial port found: $PORT"
    else
        fail "No serial port found. Plug in ESP32-C3 and re-run."
        exit 1
    fi

    # dialout group
    if id -nG | grep -qw dialout; then
        ok "User in dialout group"
    else
        warn "User not in dialout group. Run: sudo usermod -a -G dialout $USER"
        echo "  Using sg dialout -c as fallback for this session."
    fi
fi

# Tailscale (check for remote mode)
if [ "$MODE" = "remote" ]; then
    if command -v tailscale &>/dev/null; then
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [ -n "$TS_IP" ]; then
            ok "Tailscale connected: $TS_IP"
        else
            warn "Tailscale installed but not connected. Run: sudo tailscale up"
        fi
    else
        warn "Tailscale not found. Install: curl -fsSL https://tailscale.com/install.sh | sh"
    fi

    # Test connectivity to light server
    echo "  Testing connection to ${LIGHT_HOST}:${LIGHT_PORT}..."
    if curl -sf --max-time 3 "http://${LIGHT_HOST}:${LIGHT_PORT}/ping" >/dev/null 2>&1; then
        ok "Traffic light API reachable"
    else
        warn "Cannot reach traffic light API at ${LIGHT_HOST}:${LIGHT_PORT}"
        echo "  Make sure traffic_light_server.py is running on the light machine."
    fi
fi

echo ""

# ── 2. Flash firmware (local mode only) ─────────────────────────────

if [ "$MODE" = "local" ]; then
    echo "▸ Flashing firmware..."

    "$ARDUINO_CLI" compile --fqbn esp32:esp32:XIAO_ESP32C3 \
        "$PROJECT_DIR/firmware/main/traffic_light.ino" 2>/dev/null

    sg dialout -c "$ARDUINO_CLI upload --fqbn esp32:esp32:XIAO_ESP32C3 --port $PORT $PROJECT_DIR/firmware/main/traffic_light.ino" 2>/dev/null

    ok "Firmware flashed to $PORT"
    echo ""

    echo "▸ Testing LEDs (3 seconds per color)..."

    sg dialout -c "python3 $PROJECT_DIR/scripts/traffic_light.py test" >/dev/null 2>&1
    sleep 4
    sg dialout -c "python3 $PROJECT_DIR/scripts/traffic_light.py idle" >/dev/null 2>&1

    ok "Test complete. Did you see red → yellow → green?"
    echo ""
fi

# ── 3. Install hook scripts ────────────────────────────────────────

echo "▸ Installing Hermes hook scripts..."

mkdir -p "$AGENT_HOOKS"

for hook in working waiting idle; do
    src="$PROJECT_DIR/hermes-hooks/traffic-light-${hook}.sh"
    dst="$AGENT_HOOKS/traffic-light-${hook}.sh"
    # Copy and set the light host/port for remote mode
    if [ "$MODE" = "remote" ]; then
        sed -e "s|100.64.0.1|${LIGHT_HOST}|g" \
            -e "s|9090|${LIGHT_PORT}|g" \
            "$src" > "$dst"
    else
        cp "$src" "$dst"
    fi
    chmod +x "$dst"
    ok "$dst"
done

echo ""

# ── 4. Configure Hermes ───────────────────────────────────────────

echo "▸ Configuring Hermes shell hooks..."

python3 - "$CONFIG" "$PROJECT_DIR" "$ALLOWLIST" "$LIGHT_HOST" "$LIGHT_PORT" << 'PYEOF'
import sys, json, yaml

config_path, project_dir, allowlist_path, light_host, light_port = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

with open(config_path, 'r') as f:
    cfg = yaml.safe_load(f)

import os
home = os.environ.get('HOME', '/home/user')
hooks_dir = f"{home}/.hermes/agent-hooks"

cfg['hooks'] = {
    'pre_llm_call': [
        {'command': f'{hooks_dir}/traffic-light-working.sh'}
    ],
    'pre_approval_request': [
        {'command': f'{hooks_dir}/traffic-light-waiting.sh'}
    ],
    'post_llm_call': [
        {'command': f'{hooks_dir}/traffic-light-idle.sh'}
    ],
}
cfg['hooks_auto_accept'] = True

with open(config_path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

# Write allowlist
allowlist = {
    'approvals': [
        {'event': 'pre_llm_call', 'command': f'{hooks_dir}/traffic-light-working.sh'},
        {'event': 'pre_approval_request', 'command': f'{hooks_dir}/traffic-light-waiting.sh'},
        {'event': 'post_llm_call', 'command': f'{hooks_dir}/traffic-light-idle.sh'},
    ]
}
with open(allowlist_path, 'w') as f:
    json.dump(allowlist, f, indent=2)

print("OK")
PYEOF

ok "Hermes config updated"
ok "Shell hooks allowlisted"
echo ""

# ── 5. Verify ──────────────────────────────────────────────────────

echo "▸ Verifying..."
echo ""
hermes hooks list 2>/dev/null || warn "hermes CLI not found — verify manually with: hermes hooks list"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║            Setup Complete! 🚦             ║"
echo "╠═══════════════════════════════════════════╣"
echo "║  🟢 Green  — agent working                ║"
echo "║  🔴 Red    — awaiting approval             ║"
echo "║  🟡 Yellow — agent idle                    ║"
echo "╠═══════════════════════════════════════════╣"
if [ "$MODE" = "remote" ]; then
echo "║  Light server: ${LIGHT_HOST}:${LIGHT_PORT}       "
echo "║                                            ║"
echo "║  On the LIGHT machine, run:                ║"
echo "║  $ python3 scripts/traffic_light_server.py ║"
echo "║                                            ║"
else
echo "║  Light is on this machine (local USB)      ║"
fi
echo "║                                            ║"
echo "║  Restart gateway to activate hooks:        ║"
echo "║  $ hermes gateway restart                  ║"
echo "║  (from a SEPARATE terminal)                ║"
echo "╚═══════════════════════════════════════════╝"
