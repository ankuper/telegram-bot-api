# telegram-bot-api with Type3 (teleproto3) transport.
# Multi-stage: libteleproto3 -> telegram-bot-api built against ankuper/tdlib -> slim runtime.
# Image: ghcr.io/ankuper/telegram-bot-api
#
# Build args let CI pin exact refs.
ARG TELEPROTO3_REF=main
ARG TDLIB_REF=teleproto3-support
ARG BOT_API_REF=master

# ─── Build stage ──────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake g++ make git zlib1g-dev libssl-dev gperf ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 1) libteleproto3 (Type3 client lib) — Option B: build from source, no release artifacts yet.
ARG TELEPROTO3_REF
RUN git clone --depth 1 --branch "${TELEPROTO3_REF}" \
        https://github.com/ankuper/teleproto3.git /teleproto3 \
    && cmake -S /teleproto3/lib -B /teleproto3/lib/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /teleproto3/lib/build -j"$(nproc)" \
    && cp /teleproto3/lib/build/libteleproto3.a /usr/local/lib/libteleproto3.a \
    && cp /teleproto3/lib/include/t3.h /usr/local/include/t3.h

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
