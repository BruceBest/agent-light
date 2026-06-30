#!/usr/bin/env bash
# Hermes Traffic Light — red (waiting for approval)
# Fires on: pre_approval_request
cat - >/dev/null
sg dialout -c "python3 HERMES_TL_DIR/scripts/traffic_light.py waiting" >/dev/null 2>&1 &
printf '{}\n'
