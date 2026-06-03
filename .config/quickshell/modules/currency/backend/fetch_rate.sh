#!/usr/bin/env bash
# Usage: fetch_rate.sh <amount> <from> <to>
# Prints one JSON object to stdout:
#   {"amount":100,"from":"USD","to":"EUR","converted":92.35,"rate":0.9235,"date":"2024-05-17"}
# On failure:
#   {"error":"..."}

amount="${1:-}"
from="${2:-}"
to="${3:-}"

if [[ -z "$amount" || -z "$from" || -z "$to" ]]; then
    jq -cn --arg msg "missing arguments" '{error:$msg}'
    exit 0
fi

from="${from^^}"
to="${to^^}"

if ! [[ "$amount" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    jq -cn --arg msg "invalid amount" '{error:$msg}'
    exit 0
fi

if ! [[ "$from" =~ ^[A-Z]{3}$ && "$to" =~ ^[A-Z]{3}$ ]]; then
    jq -cn --arg msg "invalid currency code" '{error:$msg}'
    exit 0
fi

if [[ "$from" == "$to" ]]; then
    jq -cn --arg msg "currencies must differ" '{error:$msg}'
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    jq -cn --arg msg "curl not found" '{error:$msg}'
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    jq -cn --arg msg "jq not found" '{error:$msg}'
    exit 0
fi

response=$(curl -sfL --max-time 8 \
    "https://api.frankfurter.app/latest?amount=${amount}&from=${from}&to=${to}") || {
    jq -cn --arg msg "rate lookup failed" '{error:$msg}'
    exit 0
}

jq -cn \
    --argjson amount "$amount" \
    --arg from "$from" \
    --arg to "$to" \
    --argjson payload "$response" \
    '
      if ($payload.rates[$to] | type) != "number" then
        {error: "unsupported currency pair"}
      else
        ($payload.rates[$to]) as $converted |
        {
          amount: $amount,
          from: $from,
          to: $to,
          converted: $converted,
          rate: (if $amount == 0 then 0 else $converted / $amount end),
          date: ($payload.date // "")
        }
      end
    '
