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

![Hardware wiring](images/list.jpg)

## Quick Start

### 1. Install dependencies

```bash
# Arduino CLI
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR=~/.local/bin sh

# ESP32 platform
~/.local/bin/arduino-cli core update-index
~/.local/bin/arduino-cli core install esp32:esp32

# Python serial library
pip3 install pyserial

# Add yourself to dialout group (serial port access)
sudo usermod -a -G dialout $USER
```

### 2. Clone and set up

```bash
git clone https://github.com/BruceBest/agent-light.git ~/agent-light
cd ~/agent-light
git checkout hermes
bash scripts/setup.sh
```

`setup.sh` does everything:
- Compiles and flashes firmware to the ESP32-C3
- Tests all three LEDs
- Installs Hermes shell hook scripts
- Configures `~/.hermes/config.yaml`
- Allowlists the hooks

### 3. Restart Hermes gateway

```bash
# From a SEPARATE terminal (not inside Hermes)
hermes gateway restart
```

That's it. The light now switches automatically.

## How It Works

```
You send a message
  → Hermes fires pre_llm_call
    → hook script sends "working" over USB serial
      → 🟢 green blinks

Agent wants to run sudo/rm/etc
  → Hermes fires pre_approval_request
    → hook script sends "waiting" over USB serial
      → 🔴 red blinks

Agent finishes responding
  → Hermes fires post_llm_call
    → hook script sends "idle" over USB serial
      → 🟡 yellow steady
```

### Hook Event Mapping

| Hermes Event | Serial Command | Light | Meaning |
|-------------|---------------|-------|---------|
| `pre_llm_call` | `working` | 🟢 green blink | Agent processing |
| `pre_approval_request` | `waiting` | 🔴 red blink | Needs user approval |
| `post_llm_call` | `idle` | 🟡 yellow steady | Agent idle |

Hook scripts run as background subprocesses — they never block the agent.

## Manual Control

```bash
python3 scripts/traffic_light.py working  # green blink
python3 scripts/traffic_light.py waiting  # red blink
python3 scripts/traffic_light.py idle     # yellow steady
python3 scripts/traffic_light.py test     # cycle R→Y→G
python3 scripts/traffic_light.py off      # all off
python3 scripts/traffic_light.py status   # query state
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

## Daemon Mode

Watch a PID file and auto-switch based on process liveness:

```bash
python3 scripts/traffic_light.py daemon --pid /tmp/hermes.pid --interval 2
```

- Process alive + heartbeat fresh → 🟢 working
- Process alive + heartbeat stale → 🔴 waiting
- Process gone → 🟡 idle

## Project Structure

```
agent-light/
├── firmware/
│   ├── main/traffic_light.ino        # Main firmware (serial command handler)
│   └── diagnostic/diagnostic.ino     # Pin diagnostic tool
├── hermes-hooks/
│   ├── traffic-light-working.sh      # pre_llm_call → green
│   ├── traffic-light-waiting.sh      # pre_approval_request → red
│   └── traffic-light-idle.sh         # post_llm_call → yellow
├── scripts/
│   ├── traffic_light.py              # Serial bridge (CLI + Python API + Daemon)
│   └── setup.sh                      # One-shot installer
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
# Flash diagnostic firmware (tests each pin for 3 seconds)
~/.local/bin/arduino-cli compile --fqbn esp32:esp32:esp32c3 \
  firmware/diagnostic/diagnostic.ino
sg dialout -c "~/.local/bin/arduino-cli upload --fqbn esp32:esp32:esp32c3 \
  --port /dev/ttyACM0 firmware/diagnostic/diagnostic.ino"

# Watch which LED lights up at each step
# Then update the pin definitions in firmware/main/traffic_light.ino
```

> The DORHEA ESP32-C3 Mini labels its pins as GPIO numbers directly (0, 1, 2, ...).
> If you use a different board (e.g. Seeed XIAO ESP32-C3), check its pinout diagram —
> the physical pin labeled "D0" may map to a different GPIO number.

### ESP32-C3 not entering flash mode

The DORHEA ESP32-C3 Mini has BOOT and RESET buttons. To enter flash mode:

1. Hold the **BOOT** button
2. Tap and release the **RESET** button
3. Release **BOOT**
4. Run the upload command

### Hooks not firing

```bash
hermes hooks list
# Should show 3 hooks, all ✓ allowed

hermes gateway restart  # reload after config changes
```

### Port override

```bash
TRAFFIC_LIGHT_PORT=/dev/ttyACM0 python3 scripts/traffic_light.py test
```

## Claude Code Support

The original Claude Code integration from [upstream](https://github.com/eternityspring/agent-light) is available on the `main` branch. This `hermes` branch is specifically for Hermes Agent.

## Credits

- **Original project**: [eternityspring/agent-light](https://github.com/eternityspring/agent-light) by [@eternityspring](https://github.com/eternityspring)
- **Hermes adaptation**: [BruceBest/agent-light](https://github.com/BruceBest/agent-light) (this fork)

## License

MIT
