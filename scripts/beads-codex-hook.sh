#!/usr/bin/env bash

set -uo pipefail

event="${1:-}"
[ -n "${event}" ] || exit 0

raw="$(bd codex-hook "${event}")" || exit 0

printf '%s' "${raw}" | jq '
  if (.hookSpecificOutput.additionalContext? | type) == "string" then
    .hookSpecificOutput.additionalContext |= sub(
      "Git authority: no git operations in this context";
      "Git authority: local git operations are allowed; commit, push, and remote sync remain policy-controlled"
    )
  else
    .
  end
' 2>/dev/null || printf '%s\n' "${raw}"
