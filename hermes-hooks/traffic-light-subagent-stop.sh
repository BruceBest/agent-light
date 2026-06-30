#!/usr/bin/env bash
# Hermes Traffic Light — flash yellow (subagent stopped)
# Fires on: subagent_stop
# Quick yellow flash = subagent done notification, then back to green (working)
cat - >/dev/null
LIGHT_HOST="${TRAFFIC_LIGHT_HOST:-100.120.105.44}"
LIGHT_PORT="${TRAFFIC_LIGHT_PORT:-9090}"
# Flash yellow briefly, then return to working (green)
curl -sf --max-time 2 "http://${LIGHT_HOST}:${LIGHT_PORT}/idle" >/dev/null 2>&1
sleep 0.4
curl -sf --max-time 2 "http://${LIGHT_HOST}:${LIGHT_PORT}/working" >/dev/null 2>&1 &
printf '{}\n'
