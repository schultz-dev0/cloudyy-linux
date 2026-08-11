#!/usr/bin/env bash
# Usage: fetch_rate.sh <amount> <from> <to>
# Prints one JSON object to stdout:
#   {"amount":100,"from":"USD","to":"EUR","converted":92.35,"rate":0.9235,"date":"2024-05-17"}
# On failure:
#   {"error":"..."}
# Uses ~/.cache/cloudyy/currency/<FROM>_<TO>.json for offline/stale fallback.

amount="${1:-}"
from="${2:-}"
to="${3:-}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cloudyy/currency"

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

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"error":"jq not found"}'
    exit 0
fi

cache_file="${cache_dir}/${from}_${to}.json"

emit_from_cache() {
    local stale_flag="${1:-false}"
    [[ -f "$cache_file" ]] || return 1
    jq -cn \
        --argjson amount "$amount" \
        --arg from "$from" \
        --arg to "$to" \
        --argjson stale "$stale_flag" \
        --slurpfile cache "$cache_file" \
        '
          ($cache[0].rate // null) as $rate |
          if ($rate | type) != "number" then
            empty
          else
            {
              amount: $amount,
              from: $from,
              to: $to,
              converted: ($amount * $rate),
              rate: $rate,
              date: ($cache[0].date // ""),
              stale: $stale,
              cached: true
            }
          end
        ' 2>/dev/null
}

if ! command -v curl >/dev/null 2>&1; then
    if out=$(emit_from_cache true); [[ -n "$out" ]]; then
        printf '%s\n' "$out"
    else
        jq -cn --arg msg "curl not found" '{error:$msg}'
    fi
    exit 0
fi

response=$(curl -sfL --max-time 8 \
    "https://api.frankfurter.app/latest?amount=${amount}&from=${from}&to=${to}") || {
    if out=$(emit_from_cache true); [[ -n "$out" ]]; then
        printf '%s\n' "$out"
    else
        jq -cn --arg msg "rate lookup failed" '{error:$msg}'
    fi
    exit 0
}

result=$(jq -cn \
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
    ')

if jq -e '.error' >/dev/null 2>&1 <<<"$result"; then
    if out=$(emit_from_cache true); [[ -n "$out" ]]; then
        printf '%s\n' "$out"
    else
        printf '%s\n' "$result"
    fi
    exit 0
fi

mkdir -p "$cache_dir"
jq -cn --argjson payload "$result" \
    '{rate: $payload.rate, date: ($payload.date // ""), from: $payload.from, to: $payload.to}' \
    >"$cache_file" 2>/dev/null || true

printf '%s\n' "$result"
