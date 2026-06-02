#!/bin/sh
# Entry point: wire the Type3 proxy + creds into telegram-bot-api, then exec it.
set -eu

# --- credentials: bundled default with env override (BYO for production) ---
# NOTE: replace these placeholders with a real default app id/hash before publishing,
# or leave empty to force BYO. A single shared api_id is a convenience for first-run
# only — it is a shared point of revocation; production should set its own.
: "${TELEGRAM_API_ID:=${BUNDLED_API_ID:-}}"
: "${TELEGRAM_API_HASH:=${BUNDLED_API_HASH:-}}"
if [ -z "${TELEGRAM_API_ID}" ] || [ -z "${TELEGRAM_API_HASH}" ]; then
  echo "ERROR: TELEGRAM_API_ID / TELEGRAM_API_HASH not set and no bundled default baked in." >&2
  echo "       Get them at https://my.telegram.org and pass with -e." >&2
  exit 1
fi

# --- Type3 / teleproto3 proxy (required) ---
: "${T3_PROXY_HOST:?set T3_PROXY_HOST}"
: "${T3_PROXY_PORT:?set T3_PROXY_PORT}"
: "${T3_SECRET:?set T3_SECRET (0xff + 16-byte key + UTF-8 domain, hex)}"

BOT_API_PORT="${BOT_API_PORT:-8081}"
TELEGRAM_WORK_DIR="${TELEGRAM_WORK_DIR:-/var/lib/telegram-bot-api}"
mkdir -p "${TELEGRAM_WORK_DIR}"

# VERIFY (runtime gate): stock telegram-bot-api has NO proxy option. The Type3 proxy
# must be injected into each bot's TDLib instance via add_proxy(proxyTypeMtproto{secret}).
# That injection is the patch this repo will carry (env -> add_proxy). Until that patch
# lands, these env vars are read by the patched server:
export T3_PROXY_HOST T3_PROXY_PORT T3_SECRET

exec /usr/local/bin/telegram-bot-api \
  --api-id="${TELEGRAM_API_ID}" \
  --api-hash="${TELEGRAM_API_HASH}" \
  --http-port="${BOT_API_PORT}" \
  --dir="${TELEGRAM_WORK_DIR}" \
  --local \
  "$@"
