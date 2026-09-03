#!/usr/bin/env bash

set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
if printf '%s' "${INPUT}" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
  exit 0
fi

command -v bd >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

CWD="$(printf '%s' "${INPUT}" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "${CWD}" ] && [ -d "${CWD}" ] || exit 0
[ ! -f "${CWD}/.beads-optout" ] || exit 0
[ -d "${CWD}/.beads" ] || exit 0

STALE_SEC="${BD_STOP_STALE_SEC:-900}"
COOLDOWN_SEC="${BD_STOP_COOLDOWN_SEC:-900}"
RAW="$(cd "${CWD}" && bd list --status=in_progress --json 2>/dev/null)" || exit 0
printf '%s' "${RAW}" | jq -e 'type == "array"' >/dev/null 2>&1 || exit 0

NOW="$(date +%s)"
KEY="$(printf '%s' "${CWD}" | cksum | cut -d' ' -f1)"
STAMP="${TMPDIR:-/tmp}/my-codex-rules-beads-nudge-${KEY}"
if [ -f "${STAMP}" ]; then
  LAST="$(sed -n '1p' "${STAMP}" 2>/dev/null || printf '0')"
  case "${LAST}" in ''|*[!0-9]*) LAST=0 ;; esac
  [ $((NOW - LAST)) -ge "${COOLDOWN_SEC}" ] || exit 0
fi

STALE_LIST="$(printf '%s' "${RAW}" | jq -r \
  --argjson now "${NOW}" --argjson threshold "${STALE_SEC}" '
    [.[]
      | select((.updated_at // empty) != null)
      | select(($now - (.updated_at | fromdateiso8601)) >= $threshold)
      | "\(.id) \(.title)"
    ][:5] | .[]' 2>/dev/null)"
[ -n "${STALE_LIST}" ] || exit 0

printf '%s' "${NOW}" > "${STAMP}"
REASON="未更新のBeads課題があります。進捗または判明事項をbd noteで記録してから終了してください: $(printf '%s' "${STALE_LIST}" | paste -sd ';' -)"
jq -nc --arg reason "${REASON}" '{decision:"block", reason:$reason}'
