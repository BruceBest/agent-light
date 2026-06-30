#!/bin/bash
# Hermes Traffic Light — One-shot setup
# Flash firmware, install hooks, configure Hermes shell hooks.
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

echo "╔══════════════════════════════════════╗"
echo "║    Hermes Traffic Light — Setup      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Check prerequisites ──────────────────────────────────────────

echo "▸ Checking prerequisites..."

# Python serial
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
    fail "No serial port found. Plug in XIAO ESP32-C3 and re-run."
    exit 1
fi

# dialout group
if id -nG | grep -qw dialout; then
    ok "User in dialout group"
else
    warn "User not in dialout group. Run: sudo usermod -a -G dialout $USER"
    echo "  Using sg dialout -c as fallback for this session."
fi

echo ""

# ── 2. Flash firmware ──────────────────────────────────────────────

echo "▸ Flashing firmware..."

"$ARDUINO_CLI" compile --fqbn esp32:esp32:XIAO_ESP32C3 \
    "$PROJECT_DIR/firmware/main/traffic_light.ino" 2>/dev/null

sg dialout -c "$ARDUINO_CLI upload --fqbn esp32:esp32:XIAO_ESP32C3 --port $PORT $PROJECT_DIR/firmware/main/traffic_light.ino" 2>/dev/null

ok "Firmware flashed to $PORT"
echo ""

# ── 3. Verify hardware ─────────────────────────────────────────────

echo "▸ Testing LEDs (3 seconds per color)..."

sg dialout -c "python3 $PROJECT_DIR/scripts/traffic_light.py test" >/dev/null 2>&1
sleep 4
sg dialout -c "python3 $PROJECT_DIR/scripts/traffic_light.py idle" >/dev/null 2>&1

ok "Test complete. Did you see red → yellow → green?"
echo ""

# ── 4. Install hook scripts ────────────────────────────────────────

echo "▸ Installing Hermes hook scripts..."

mkdir -p "$AGENT_HOOKS"

for hook in working waiting idle; do
    src="$PROJECT_DIR/hermes-hooks/traffic-light-${hook}.sh"
    dst="$AGENT_HOOKS/traffic-light-${hook}.sh"
    # Replace placeholder with actual path
    sed "s|HERMES_TL_DIR|$PROJECT_DIR|g" "$src" > "$dst"
    chmod +x "$dst"
    ok "$dst"
done

echo ""

# ── 5. Configure Hermes ───────────────────────────────────────────

echo "▸ Configuring Hermes shell hooks..."

# Use Python to safely modify YAML
python3 - "$CONFIG" "$PROJECT_DIR" "$ALLOWLIST" << 'PYEOF'
import sys, json, yaml

config_path, project_dir, allowlist_path = sys.argv[1], sys.argv[2], sys.argv[3]
hooks_dir = f"{project_dir}/hermes-hooks"

with open(config_path, 'r') as f:
    cfg = yaml.safe_load(f)

cfg['hooks'] = {
    'pre_llm_call': [
        {'command': f'{project_dir}/hermes-hooks/traffic-light-working.sh'.replace(
            hooks_dir, f"{__import__("os").environ.get('HOME', '/home/user')}/.hermes/agent-hooks")}
    ],
    'pre_approval_request': [
        {'command': f'{project_dir}/hermes-hooks/traffic-light-waiting.sh'.replace(
            hooks_dir, f"{__import__("os").environ.get('HOME', '/home/user')}/.hermes/agent-hooks")}
    ],
    'post_llm_call': [
        {'command': f'{project_dir}/hermes-hooks/traffic-light-idle.sh'.replace(
            hooks_dir, f"{__import__("os").environ.get('HOME', '/home/user')}/.hermes/agent-hooks")}
    ],
}
cfg['hooks_auto_accept'] = True

with open(config_path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

# Write allowlist
import os
home = os.environ.get('HOME', '/home/user')
allowlist = {
    'approvals': [
        {'event': 'pre_llm_call', 'command': f'{home}/.hermes/agent-hooks/traffic-light-working.sh'},
        {'event': 'pre_approval_request', 'command': f'{home}/.hermes/agent-hooks/traffic-light-waiting.sh'},
        {'event': 'post_llm_call', 'command': f'{home}/.hermes/agent-hooks/traffic-light-idle.sh'},
    ]
}
with open(allowlist_path, 'w') as f:
    json.dump(allowlist, f, indent=2)

print("OK")
PYEOF

ok "Hermes config updated"
ok "Shell hooks allowlisted"
echo ""

# ── 6. Verify ──────────────────────────────────────────────────────

echo "▸ Verifying..."
echo ""
hermes hooks list 2>/dev/null || warn "hermes CLI not found — verify manually with: hermes hooks list"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║         Setup Complete! 🚦           ║"
echo "╠══════════════════════════════════════╣"
echo "║  🟢 Green  — agent working           ║"
echo "║  🔴 Red    — awaiting approval        ║"
echo "║  🟡 Yellow — agent idle               ║"
echo "╠══════════════════════════════════════╣"
echo "║  Restart gateway to activate hooks:   ║"
echo "║  $ hermes gateway restart             ║"
echo "║  (from a SEPARATE terminal)           ║"
echo "╚══════════════════════════════════════╝"
