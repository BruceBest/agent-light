# Hermes Traffic Light 🚦

A physical traffic light for [Hermes Agent](https://hermes-agent.nousresearch.com) — shows agent status via RGB LEDs on an ESP32-C3.

```
🟢 Green blink  → agent is processing your message
🔴 Red blink    → agent needs you to approve a command
🟡 Yellow steady → agent is idle / done
```

Uses [Hermes Shell Hooks](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks) — the light switches automatically at the framework level. Zero tool call overhead.

> **Forked from [eternityspring/agent-light](https://github.com/eternityspring/agent-light)** — the original Claude Code physical traffic light. This fork adapts it for Hermes Agent with a Python bridge and native shell hook integration.

## Hardware

You need three things:

| # | Item | Link | Price |
|---|------|------|-------|
| 1 | DORHEA ESP32-C3 Mini Dev Board (5-pack) | [Amazon](https://www.amazon.com/dp/B0GFDMJDG6) | ~$18 |
| 2 | Adeept Mini Traffic Light LED Module (5-pack) | [Amazon](https://www.amazon.com/dp/B097GK4S2D) | ~$9 |
| 3 | ELEGOO Dupont Jumper Wires (120pcs) | [Amazon](https://www.amazon.com/dp/B01EV70C78) | ~$7 |

**Total: ~$34** (you get 5 of each — enough to build 5 traffic lights or have spares).

### Wiring

Connect the Adeept traffic light module to the ESP32-C3 with Dupont wires:

| Adeept Module Pin | ESP32-C3 Pin | GPIO |
|-------------------|-------------|------|
| R (Red) | GPIO2 | 2 |
| Y (Yellow) | GPIO1 | 1 |
| G (Green) | GPIO0 | 0 |
| VCC | 5V (or 3.3V) | — |
| GND | GND | — |

> ⚠️ The Adeept module has built-in current-limiting resistors. No external resistors needed.
> ⚠️ The module is common cathode — `HIGH` turns the LED on, `LOW` turns it off.

## Two Modes

The traffic light supports two modes — **local** (light on the same machine as Hermes) and **remote** (light on a different machine, connected via Tailscale/LAN).

### Local Mode

```
Hermes (this machine) → hook → serial → USB → ESP32-C3 → light
```

The light plugs directly into the machine running Hermes. Simplest setup.

### Remote Mode

```
Hermes (desktop) → hook → curl → Tailscale/LAN → API server (laptop) → serial → USB → light
```

The light plugs into a different machine (e.g. your laptop). Hermes hooks send HTTP requests over Tailscale to a small API server on the light machine.

**Why remote?** You want the light next to you (on your laptop) while Hermes runs on a headless server (in a closet, cloud, etc).

## Quick Start — Local Mode

```bash
# 1. Install dependencies
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR=~/.local/bin sh
~/.local/bin/arduino-cli core update-index
~/.local/bin/arduino-cli core install esp32:esp32
pip3 install pyserial
sudo usermod -a -G dialout $USER

# 2. Clone and set up
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
bash scripts/setup.sh

# 3. Restart Hermes gateway (from a separate terminal)
hermes gateway restart
```

## Quick Start — Remote Mode

### On the light machine (e.g. your laptop):

```bash
# 1. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. Clone and install dependencies
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
pip3 install pyserial
sudo usermod -a -G dialout $USER

# 3. Flash firmware (plug in ESP32-C3 via USB)
bash scripts/setup.sh   # flashes firmware + tests LEDs

# 4. Start the API server
python3 scripts/traffic_light_server.py --port 9090

# Note your Tailscale IP:
tailscale ip -4
# → e.g. 100.64.0.2
```

### On the Hermes machine (e.g. your desktop):

```bash
# 1. Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. Clone and set up in remote mode
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
bash scripts/setup.sh --remote --light-host 100.64.0.2 --light-port 9090

# 3. Restart Hermes gateway (from a separate terminal)
hermes gateway restart
```

## How It Works

```
You send a message
  → Hermes fires pre_llm_call
    → hook script curls API server / sends to serial
      → 🟢 green blinks

Agent wants to run sudo/rm/etc
  → Hermes fires pre_approval_request
    → hook script curls API server / sends to serial
      → 🔴 red blinks

Agent finishes responding
  → Hermes fires post_llm_call
    → hook script curls API server / sends to serial
      → 🟡 yellow steady
```

### Hook Event Mapping

| Hermes Event | Command | Light | Meaning |
|-------------|---------|-------|---------|
| `pre_llm_call` | `working` | 🟢 green blink | Agent processing |
| `pre_approval_request` | `waiting` | 🔴 red blink | Needs user approval |
| `post_llm_call` | `idle` | 🟡 yellow steady | Agent idle |

Hook scripts run as background subprocesses — they never block the agent.

## Manual Control

```bash
# Local (direct serial)
python3 scripts/traffic_light.py working  # green blink
python3 scripts/traffic_light.py waiting  # red blink
python3 scripts/traffic_light.py idle     # yellow steady
python3 scripts/traffic_light.py test     # cycle R→Y→G

# Remote (via API)
curl http://100.64.0.2:9090/working
curl http://100.64.0.2:9090/waiting
curl http://100.64.0.2:9090/idle
curl http://100.64.0.2:9090/test
curl http://100.64.0.2:9090/ping
```

## Python API

```python
from traffic_light import TrafficLight

tl = TrafficLight()
tl.working()   # green blink
tl.waiting()   # red blink
tl.idle()      # yellow steady
tl.close()

# Context manager (auto-idle on exit):
with TrafficLight() as tl:
    tl.working()
    # ... agent work ...
```

## Remote API Server

Run on the machine with the USB traffic light attached:

```bash
python3 scripts/traffic_light_server.py              # default port 9090
python3 scripts/traffic_light_server.py --port 8888  # custom port
TRAFFIC_LIGHT_PORT=/dev/ttyACM0 python3 scripts/traffic_light_server.py  # override serial port
```

### Endpoints

| Endpoint | Effect |
|----------|--------|
| `GET /working` | 🟢 green blink |
| `GET /waiting` | 🔴 red blink |
| `GET /idle` | 🟡 yellow steady |
| `GET /off` | All off |
| `GET /test` | Cycle R→Y→G |
| `GET /status` | Query current state |
| `GET /ping` | Health check |

### Systemd service (auto-start on boot)

```bash
# Copy and edit the service file
cp scripts/traffic-light-api.service ~/.config/systemd/user/
sed -i "s|HOME_DIR|$HOME|g" ~/.config/systemd/user/traffic-light-api.service

# Enable boot-time auto-start (starts before login)
loginctl enable-linger

# Enable and start
systemctl --user daemon-reload
systemctl --user enable traffic-light-api.service
systemctl --user start traffic-light-api.service
```

## Project Structure

```
agent-light/
├── firmware/
│   ├── traffic_light/traffic_light.ino # Main firmware (serial command handler)
│   └── diagnostic/diagnostic.ino     # Pin diagnostic tool
├── hermes-hooks/
│   ├── traffic-light-working.sh      # pre_llm_call → green
│   ├── traffic-light-waiting.sh      # pre_approval_request → red
│   └── traffic-light-idle.sh         # post_llm_call → yellow
├── scripts/
│   ├── traffic_light.py              # Serial bridge (CLI + Python API + Daemon)
│   ├── traffic_light_server.py       # Remote API server (HTTP → serial)
│   ├── traffic-light-api.service     # Systemd unit for the API server
│   └── setup.sh                      # One-shot installer (local + remote modes)
├── images/                           # Original photos from upstream
└── README.md
```

## Troubleshooting

### Serial port not found

```bash
ls /dev/ttyACM* /dev/ttyUSB*
# Empty? Unplug and replug the USB-C cable.
# Still empty? Hold BOOT button, tap RESET, then release BOOT (flash mode).
```

### Permission denied

```bash
groups | grep dialout
# If missing:
sudo usermod -a -G dialout $USER
# Then re-login (or: sudo chmod 666 /dev/ttyACM0 for immediate fix)
```

### Only one LED lights up

The GPIO pin mapping is wrong. Run the diagnostic firmware:

```bash
~/.local/bin/arduino-cli compile --fqbn esp32:esp32:XIAO_ESP32C3 firmware/diagnostic/diagnostic.ino
sg dialout -c "~/.local/bin/arduino-cli upload --fqbn esp32:esp32:XIAO_ESP32C3 --port /dev/ttyACM0 firmware/diagnostic/diagnostic.ino"
# Watch which LED lights up at each step
# Then update pin definitions in firmware/traffic_light/traffic_light.ino
```

### Cannot reach remote API server

```bash
# Check Tailscale is connected
tailscale status

# Check the API server is running
curl http://100.64.0.2:9090/ping

# Check firewall
sudo ufw allow 9090/tcp  # if ufw is active
```

### Hooks not firing

```bash
hermes hooks list       # Should show 3 hooks, all ✓ allowed
hermes gateway restart  # Reload after config changes
```

### Port override

```bash
TRAFFIC_LIGHT_PORT=/dev/ttyACM0 python3 scripts/traffic_light.py test
```

## Credits

- **Original project**: [eternityspring/agent-light](https://github.com/eternityspring/agent-light) by [@eternityspring](https://github.com/eternityspring)
- **Hermes adaptation**: [BruceBest/agent-light](https://github.com/BruceBest/agent-light) (this fork)

## License

MIT
