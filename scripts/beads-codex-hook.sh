#!/usr/bin/env bash
# Existing hook registrations continue to reach the official adapter until setup runs.
set -euo pipefail
exec "${PYTHON_COMMAND:-python3}" "$(dirname "${BASH_SOURCE[0]}")/hooks/beads-hook.py" "$@"
