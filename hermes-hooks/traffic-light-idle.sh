#!/usr/bin/env bash
# Hermes Traffic Light — remote yellow (idle)
# Fires on: post_llm_call
# Sends HTTP request to traffic light API server over Tailscale/LAN
cat - >/dev/null
LIGHT_HOST="${TRAFFIC_LIGHT_HOST:-100.64.0.1}"
LIGHT_PORT="${TRAFFIC_LIGHT_PORT:-9090}"
curl -sf --max-time 2 "http://${LIGHT_HOST}:${LIGHT_PORT}/idle" >/dev/null 2>&1 &
printf '{}\n'
