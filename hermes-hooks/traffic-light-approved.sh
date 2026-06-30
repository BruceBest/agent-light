#!/usr/bin/env bash
# Hermes Traffic Light — green (back to working after approval)
# Fires on: post_approval_response
# Sends HTTP request to traffic light API server over Tailscale/LAN
cat - >/dev/null
LIGHT_HOST="${TRAFFIC_LIGHT_HOST:-100.120.105.44}"
LIGHT_PORT="${TRAFFIC_LIGHT_PORT:-9090}"
curl -sf --max-time 2 "http://${LIGHT_HOST}:${LIGHT_PORT}/working" >/dev/null 2>&1 &
printf '{}\n'
