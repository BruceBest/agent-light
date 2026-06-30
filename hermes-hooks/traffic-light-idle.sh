#!/usr/bin/env bash
# Hermes Traffic Light — yellow (idle)
# Fires on: post_llm_call
cat - >/dev/null
sg dialout -c "python3 HERMES_TL_DIR/scripts/traffic_light.py idle" >/dev/null 2>&1 &
printf '{}\n'
