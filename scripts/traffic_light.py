#!/usr/bin/env python3
"""
Hermes Traffic Light — Serial bridge for XIAO ESP32-C3.

Usage:
  CLI:    python3 traffic_light.py working
  Python: from traffic_light import TrafficLight
  Daemon: python3 traffic_light.py daemon --pid /tmp/hermes.pid

States:
  working  → green blink  (agent processing)
  waiting  → red blink     (awaiting user approval)
  idle     → yellow steady (agent idle)
  off      → all LEDs off
  test     → cycle R→Y→G
  status   → query current state
"""

import sys
import os
import glob
import time
import signal
import threading


def find_port():
    """Auto-detect XIAO ESP32-C3 serial port."""
    port = os.environ.get('TRAFFIC_LIGHT_PORT')
    if port and os.path.exists(port):
        return port
    for pattern in ['/dev/ttyACM*', '/dev/ttyUSB*']:
        ports = sorted(glob.glob(pattern))
        if ports:
            return ports[-1]
    return None


class TrafficLight:
    """Control the physical traffic light via serial."""

    VALID = {'working', 'waiting', 'idle', 'off', 'test', 'status'}

    def __init__(self, port=None, baud=115200, timeout=2):
        self.port = port or find_port()
        self.baud = baud
        self.timeout = timeout
        self._ser = None

    def _connect(self, force=False):
        import serial
        if force and self._ser and self._ser.is_open:
            self._ser.close()
            self._ser = None
        if self._ser and self._ser.is_open:
            # Verify the connection is actually alive (not a stale fd from USB hotplug)
            try:
                self._ser.write(b'\n')
                self._ser.flush()
                time.sleep(0.1)
                self._ser.reset_input_buffer()  # discard ESP32 "Unknown command:" response
            except (serial.SerialException, OSError):
                # Stale connection — close and reconnect below
                try:
                    self._ser.close()
                except Exception:
                    pass
                self._ser = None
        if not self.port:
            raise RuntimeError(
                "No serial port found. Is XIAO ESP32-C3 plugged in?\n"
                "Set TRAFFIC_LIGHT_PORT=/dev/ttyACM0 to override."
            )
        if self._ser is None:
            self._ser = serial.Serial(self.port, self.baud, timeout=self.timeout)
            time.sleep(0.5)
            self._ser.reset_input_buffer()
        return self._ser

    def send(self, cmd):
        cmd = cmd.strip().lower()
        if cmd not in self.VALID:
            raise ValueError(f"Unknown command: {cmd}. Valid: {self.VALID}")
        try:
            ser = self._connect()
            ser.write((cmd + '\n').encode())
            ser.flush()
            time.sleep(0.3)
            resp = ser.read(ser.in_waiting or 256).decode('utf-8', errors='ignore').strip()
            return resp
        except (OSError, Exception) as e:
            # Stale serial connection (e.g. USB hotplug) — force reconnect and retry once
            if isinstance(e, OSError) or 'write failed' in str(e) or 'Input/output error' in str(e):
                ser = self._connect(force=True)
                ser.write((cmd + '\n').encode())
                ser.flush()
                time.sleep(0.3)
                resp = ser.read(ser.in_waiting or 256).decode('utf-8', errors='ignore').strip()
                return resp
            raise

    def close(self):
        if self._ser and self._ser.is_open:
            self._ser.close()
            self._ser = None

    # Convenience
    def working(self):  return self.send('working')
    def waiting(self):  return self.send('waiting')
    def idle(self):     return self.send('idle')
    def off(self):      return self.send('off')
    def test(self):     return self.send('test')
    def status(self):   return self.send('status')

    # Context manager — auto-idle on exit
    def __enter__(self):
        self.working()
        return self

    def __exit__(self, *exc):
        self.idle()
        self.close()
        return False


class TrafficLightDaemon:
    """Watch a PID file and auto-switch light states."""

    def __init__(self, pid_file, heartbeat_file=None, poll_interval=2):
        self.pid_file = pid_file
        self.heartbeat_file = heartbeat_file or (pid_file + '.heartbeat')
        self.poll_interval = poll_interval
        self.light = TrafficLight()
        self._running = False
        self._state = None

    def _read_pid(self):
        try:
            return int(open(self.pid_file).read().strip())
        except (FileNotFoundError, ValueError):
            return None

    def _pid_alive(self, pid):
        if pid is None:
            return False
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    def _heartbeat_fresh(self):
        try:
            return (time.time() - os.path.getmtime(self.heartbeat_file)) < 30
        except FileNotFoundError:
            return False

    def _set_state(self, state):
        if state != self._state:
            try:
                self.light.send(state)
                self._state = state
            except Exception as e:
                print(f"Warning: {e}", file=sys.stderr)

    def run(self):
        self._running = True
        signal.signal(signal.SIGTERM, lambda *_: setattr(self, '_running', False))
        signal.signal(signal.SIGINT, lambda *_: setattr(self, '_running', False))

        print(f"Daemon started — watching {self.pid_file} (poll {self.poll_interval}s)")

        while self._running:
            pid = self._read_pid()
            alive = self._pid_alive(pid)
            fresh = self._heartbeat_fresh()

            if alive and fresh:
                self._set_state('working')
            elif alive:
                self._set_state('waiting')
            else:
                self._set_state('idle')

            time.sleep(self.poll_interval)

        self.light.idle()
        self.light.close()


def main():
    if len(sys.argv) < 2:
        print(f"""Hermes Traffic Light

Usage:
  {sys.argv[0]} <command>         Send command to traffic light
  {sys.argv[0]} daemon --pid FILE Watch process and auto-switch

Commands: working | waiting | idle | off | test | status

Daemon options:
  --pid FILE         PID file to watch (required)
  --heartbeat FILE   Heartbeat file (default: PID_FILE.heartbeat)
  --interval SECS    Poll interval (default: 2)

Environment:
  TRAFFIC_LIGHT_PORT  Override serial port auto-detection
""")
        sys.exit(1)

    cmd = sys.argv[1].lower()

    if cmd == 'daemon':
        pid_file = None
        heartbeat_file = None
        interval = 2
        i = 2
        while i < len(sys.argv):
            if sys.argv[i] == '--pid' and i + 1 < len(sys.argv):
                pid_file = sys.argv[i + 1]; i += 2
            elif sys.argv[i] == '--heartbeat' and i + 1 < len(sys.argv):
                heartbeat_file = sys.argv[i + 1]; i += 2
            elif sys.argv[i] == '--interval' and i + 1 < len(sys.argv):
                interval = int(sys.argv[i + 1]); i += 2
            else:
                i += 1
        if not pid_file:
            print("Error: --pid FILE required for daemon mode", file=sys.stderr)
            sys.exit(1)
        TrafficLightDaemon(pid_file, heartbeat_file, interval).run()
    else:
        tl = TrafficLight()
        try:
            resp = tl.send(cmd)
            if resp:
                print(resp)
        finally:
            tl.close()


if __name__ == '__main__':
    main()
