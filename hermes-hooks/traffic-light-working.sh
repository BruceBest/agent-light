#!/usr/bin/env bash
# Hermes Traffic Light — green (working)
# Fires on: pre_llm_call
cat - >/dev/null
sg dialout -c "python3 HERMES_TL_DIR/scripts/traffic_light.py working" >/dev/null 2>&1 &
printf '{}\n'
