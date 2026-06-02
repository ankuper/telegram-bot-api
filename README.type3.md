# telegram-bot-api (Type3 / teleproto3 edition)

Self-hosted [Telegram Bot API](https://github.com/tdlib/telegram-bot-api) server that
reaches Telegram **through a Type3 / teleproto3 proxy**, so bots keep working from
networks where the direct path to Telegram is blocked by DPI.

It is built against [`ankuper/tdlib`](https://github.com/ankuper/tdlib) (branch
`teleproto3-support`), which adds the client-side Type3 WebSocket / HTTP-stream
transport that stock TDLib does not have.

> **Status: scaffold / WIP.** The build recipe and proxy wiring below carry `VERIFY`
> markers where they still need a real Linux/Docker build to confirm. CI is the gate.

---

## How it works — two legs

You don't tunnel HTTPS. You **move the boundary**: run the Bot API server locally, so
the censored request never crosses the border.

```
 your bot ──HTTP──▶ 127.0.0.1:8081  (this server)
                          │ MTProto
                          ▼
                 [ Type3 / teleproto3 proxy ]  ◀── your existing endpoint (host:port:secret)
                          │ MTProto
                          ▼
                    Telegram DC
```

- The bot talks to `localhost:8081` — pure loopback, the censor sees nothing.
- Only the server's MTProto leg crosses the border, riding teleproto3 — exactly what
  teleproto3 is for. **No HTTPS is proxied.**

---

## Quickstart

You need: Docker, an existing **Type3 proxy endpoint** (host + port + secret), and a
Telegram **bot token** from [@BotFather](https://t.me/BotFather).

```bash
docker run -d --name tg-bot-api \
  -p 8081:8081 \
  -e T3_PROXY_HOST=your-proxy.example.com \
  -e T3_PROXY_PORT=443 \
  -e T3_SECRET=ff<16-byte-key-hex><domain> \
  ghcr.io/ankuper/telegram-bot-api:latest
# TELEGRAM_API_ID / TELEGRAM_API_HASH are optional — a bundled default is used for
# first-run convenience. Set them (from https://my.telegram.org) for production.
```

Then point your bot at the local server — **one line**:

| Library | Change |
|---|---|
| python-telegram-bot | `ApplicationBuilder().base_url("http://localhost:8081/bot")` |
| aiogram v3 | `TelegramAPIServer.from_base("http://localhost:8081")` |
| telegraf (Node) | `new Telegraf(token, { telegram: { apiRoot: 'http://localhost:8081' } })` |

Verify:

```bash
curl -s "http://localhost:8081/bot<TOKEN>/getMe" | jq .ok   # → true
```

---

## Configuration (env)

| Var | Required | Notes |
|---|---|---|
| `T3_PROXY_HOST` | yes | Type3 proxy host |
| `T3_PROXY_PORT` | yes | Type3 proxy port (e.g. 443) |
| `T3_SECRET` | yes | Type3 secret: `0xff` + 16-byte key + UTF-8 domain (hex) |
| `TELEGRAM_API_ID` | no | App id; bundled default if unset |
| `TELEGRAM_API_HASH` | no | App hash; bundled default if unset |
| `BOT_API_PORT` | no | Local HTTP port (default 8081) |

> **Trust:** your **bot token is never a config value** — it travels only in the HTTP
> path to `localhost`. The source is open; verify for yourself that nothing leaves the
> box except the MTProto leg through your proxy.

---

## Build

```bash
docker build -t telegram-bot-api-type3 .
```

See [`Dockerfile`](Dockerfile) — multi-stage: build `libteleproto3` → build
`telegram-bot-api` against `ankuper/tdlib` (teleproto3-support) → slim runtime.

## License

MIT (this repo's wrapper/build files). `telegram-bot-api` and TDLib are
Boost Software License 1.0, fetched at build time, not vendored here.
