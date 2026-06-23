# telegram-bot-api with Type3 (teleproto3) transport.
# Multi-stage: libteleproto3 -> telegram-bot-api built against ankuper/tdlib -> slim runtime.
# Image: ghcr.io/ankuper/telegram-bot-api
#
# Build args let CI pin exact refs.
# TELEPROTO3_REF = a teleproto3 RELEASE/TAG (policy: consume the prebuilt artifact,
# never build teleproto3 from source). Pin to a tag, not a branch.
ARG TELEPROTO3_REF=lib-v0.8.0
ARG TDLIB_REF=teleproto3-support
ARG BOT_API_REF=master

# ─── Build stage ──────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make git zlib1g-dev libssl-dev gperf ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# 1) libteleproto3 (Type3 client lib) — PREBUILT from the teleproto3 release/tag.
#    Policy (docs/release-and-branch-policy.md): never build teleproto3 from source;
#    consume the published per-platform artifact. Linux server → libteleproto3-linux-<arch>.tar.gz
#    (archive layout: lib/{libteleproto3.a,include/}).
ARG TELEPROTO3_REF
RUN ARCH="$(uname -m)" \
    && curl -fsSL "https://github.com/ankuper/teleproto3/releases/download/${TELEPROTO3_REF}/libteleproto3-linux-${ARCH}.tar.gz" \
        -o /tmp/libteleproto3.tar.gz \
    && mkdir -p /teleproto3 && tar xzf /tmp/libteleproto3.tar.gz -C /teleproto3 \
    && cp /teleproto3/lib/libteleproto3.a /usr/local/lib/libteleproto3.a \
    && cp -r /teleproto3/lib/include/. /usr/local/include/

# 2) telegram-bot-api with our Type3-patched TDLib swapped in for the td/ submodule.
ARG BOT_API_REF
ARG TDLIB_REF
RUN git clone --recursive --branch "${BOT_API_REF}" \
        https://github.com/tdlib/telegram-bot-api.git /bot-api \
    && rm -rf /bot-api/td \
    && git clone --depth 1 --branch "${TDLIB_REF}" \
        https://github.com/ankuper/tdlib.git /bot-api/td

# VERIFY (build gate): telegram-bot-api consumes TDLib via add_subdirectory(td); confirm
#   (a) the fork's CMake targets match what telegram-bot-api links (Td::TdStatic),
#   (b) the -DTELEPROTO3_* cache vars below propagate into the td subdirectory build.
# These cmake var names match ankuper/tdlib CMakeLists.txt (find_library(teleproto3)).
RUN cmake -S /bot-api -B /bot-api/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DTELEPROTO3_LIB_DIR=/usr/local/lib \
        -DTELEPROTO3_INCLUDE_DIR=/usr/local/include \
        -DT3_STATIC_LIB=ON \
    && cmake --build /bot-api/build --target install -j"$(nproc)"

# ─── Runtime stage ────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 zlib1g ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/telegram-bot-api /usr/local/bin/telegram-bot-api
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

LABEL org.opencontainers.image.title="telegram-bot-api-type3" \
      org.opencontainers.image.authors="ankuper" \
      org.opencontainers.image.source="https://github.com/ankuper/telegram-bot-api" \
      org.opencontainers.image.description="Self-hosted Telegram Bot API over Type3/teleproto3 proxy."

EXPOSE 8081
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
