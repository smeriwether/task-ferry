#!/usr/bin/env bash
set -euo pipefail

TASK_FERRY_HELPER="${1:?cloudflared path is required}"
TASK_FERRY_SIGNING_IDENTITY="${2:--}"
TASK_FERRY_CONFIGURATION="${3:-Debug}"

[[ -f "$TASK_FERRY_HELPER" ]] || exit 0

if [[ "$TASK_FERRY_CONFIGURATION" == "Release-Direct" && "$TASK_FERRY_SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --sign "$TASK_FERRY_SIGNING_IDENTITY" --options runtime --timestamp "$TASK_FERRY_HELPER"
else
  codesign --force --sign "$TASK_FERRY_SIGNING_IDENTITY" --options runtime "$TASK_FERRY_HELPER"
fi
