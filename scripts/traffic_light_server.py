#!/usr/bin/env python3
"""
Hermes Traffic Light — Remote API Server

Run this on the machine with the USB traffic light attached.
Receives HTTP commands from Hermes hooks over Tailscale (or LAN).

Usage:
  python3 traffic_light_server.py                    # default port 9090
  python3 traffic_light_server.py --port 8888        # custom port
  TRAFFIC_LIGHT_PORT=/dev/ttyACM0 python3 traffic_light_server.py  # override serial port

Endpoints:
  GET /working   → green blink
  GET /waiting   → red blink
  GET /idle      → yellow steady
  GET /off       → all off
  GET /test      → cycle R→Y→G
  GET /status    → query current state
  GET /ping      → health check
"""

import sys
import argparse

# Minimal dependencies — only stdlib + pyserial
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

sys.path.insert(0, '/'.join(__file__.rsplit('/', 1)) or '.')
from traffic_light import TrafficLight

# Shared instance (keeps serial connection open)
_tl = None

def get_light():
    global _tl
    if _tl is None:
        _tl = TrafficLight()
    return _tl


class TrafficLightHandler(BaseHTTPRequestHandler):
    """Handle GET /<command> requests."""

    VALID = {'working', 'waiting', 'idle', 'off', 'test', 'status', 'ping'}

    def do_GET(self):
        cmd = self.path.strip('/').lower().split('?')[0]

        if not cmd or cmd == 'ping':
            self._respond(200, {'ok': True, 'state': self._get_state()})
            return

        if cmd not in self.VALID:
            self._respond(400, {'error': f'Unknown command: {cmd}', 'valid': list(self.VALID)})
            return

        try:
            tl = get_light()
            result = tl.send(cmd)
            self._respond(200, {'ok': True, 'command': cmd, 'result': result})
        except Exception as e:
            self._respond(500, {'error': str(e)})

    def _get_state(self):
        try:
            tl = get_light()
            resp = tl.send('status')
            if resp.startswith('STATE:'):
                return resp[6:]
            return resp
        except Exception:
            return 'disconnected'

    def _respond(self, code, body):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def log_message(self, format, *args):
        # Compact logging
        sys.stderr.write(f"[traffic-light] {args[0]}\n")


def main():
    parser = argparse.ArgumentParser(description='Hermes Traffic Light Remote API')
    parser.add_argument('--port', type=int, default=9090, help='Listen port (default: 9090)')
    parser.add_argument('--host', default='0.0.0.0', help='Bind address (default: 0.0.0.0)')
    args = parser.parse_args()

    # Test serial connection on startup
    try:
        tl = get_light()
        state = tl.send('status')
        print(f"Traffic light connected: {state}")
    except Exception as e:
        print(f"Warning: Could not connect to traffic light: {e}")
        print("Server will start anyway — connect the light and commands will retry.")

    server = HTTPServer((args.host, args.port), TrafficLightHandler)
    print(f"Traffic Light API listening on {args.host}:{args.port}")
    print(f"Endpoints: /working /waiting /idle /off /test /status /ping")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        if _tl:
            _tl.idle()
            _tl.close()
        server.server_close()


if __name__ == '__main__':
    main()
