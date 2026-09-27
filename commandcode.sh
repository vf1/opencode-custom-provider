#!/usr/bin/env bash
exec python3 "$(dirname "$0")/models.py" \
  "https://api.commandcode.ai/provider/v1/models" \
  -o "results/commandcode.json"
