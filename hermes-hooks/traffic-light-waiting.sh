#!/usr/bin/env bash
# Hermes Traffic Light — remote red (waiting for approval)
# Fires on: pre_approval_request
# Sends HTTP request to traffic light API server over Tailscale/LAN
cat - >/dev/null
LIGHT_HOST="${TRAFFIC_LIGHT_HOST:-100.64.0.1}"
LIGHT_PORT="${TRAFFIC_LIGHT_PORT:-9090}"
curl -sf --max-time 2 "http://${LIGHT_HOST}:${LIGHT_PORT}/waiting" >/dev/null 2>&1 &
printf '{}\n'
