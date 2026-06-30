#!/usr/bin/env bash
# Hermes Traffic Light — yellow (session reset / idle)
# Fires on: on_session_reset
cat - >/dev/null
LIGHT_HOST="${TRAFFIC_LIGHT_HOST:-100.120.105.44}"
LIGHT_PORT="${TRAFFIC_LIGHT_PORT:-9090}"
curl -sf --max-time 2 "http://${LIGHT_HOST}:${LIGHT_PORT}/idle" >/dev/null 2>&1 &
printf '{}\n'
