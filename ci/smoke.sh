#!/bin/sh
# Smoke test: getMe through the local server.
#   GREEN: proxy up   -> getMe returns ok:true
#   RED  : proxy down -> getMe must fail (proves traffic really used the proxy)
# Requires: running container, BOT_TOKEN, a Type3 proxy you can toggle.
set -eu

PORT="${BOT_API_PORT:-8081}"
: "${BOT_TOKEN:?set BOT_TOKEN}"

green() {
  ok=$(curl -s --max-time 30 "http://127.0.0.1:${PORT}/bot${BOT_TOKEN}/getMe" | grep -o '"ok":true' || true)
  [ -n "$ok" ] || { echo "FAIL: getMe not ok with proxy up" >&2; exit 1; }
  echo "GREEN: getMe ok with proxy up"
}

red() {
  # caller must stop/block the Type3 proxy before invoking with arg "red"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    "http://127.0.0.1:${PORT}/bot${BOT_TOKEN}/getMe" || echo 000)
  [ "$code" != "200" ] || { echo "FAIL: getMe succeeded with proxy down — leg not enforced" >&2; exit 1; }
  echo "RED: getMe failed with proxy down (expected)"
}

case "${1:-green}" in
  green) green ;;
  red)   red ;;
  *) echo "usage: $0 [green|red]" >&2; exit 2 ;;
esac
