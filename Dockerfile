# Build stage from Dockerfile.source (adapted for musl/Alpine targets)
# Runtime stage from Dockerfile (production)
# with patches for CORS expose-headers and PostObject Location header

ARG TARGETPLATFORM
ARG BUILDPLATFORM

FROM rust:1.93-alpine AS builder

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG RUSTFS_VERSION=1.0.0-alpha.82

RUN apk add --no-cache \
      build-base \
      ca-certificates \
      curl \
      git \
      pkgconf \
      openssl-dev \
      openssl-libs-static \
      protobuf-dev \
      flatbuffers-dev \
      musl-dev \
      unzip

WORKDIR /usr/src/rustfs
RUN git clone --depth 1 --branch ${RUSTFS_VERSION} https://github.com/rustfs/rustfs.git .

COPY patches/ patches/
RUN git apply patches/expose-location-header.patch \
    && git apply patches/post-object-location-header.patch

RUN ./scripts/static.sh

ENV CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
    CARGO_INCREMENTAL=0 \
    CARGO_PROFILE_RELEASE_DEBUG=false \
    CARGO_PROFILE_RELEASE_SPLIT_DEBUGINFO=off \
    CARGO_PROFILE_RELEASE_STRIP=symbols

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/src/rustfs/target \
    cargo run --bin gproto

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/src/rustfs/target \
    cargo build --release --locked --bin rustfs -j "$(nproc)" && \
    install -m 0755 target/release/rustfs /usr/local/bin/rustfs

# --- Runtime stage from upstream Dockerfile ---

FROM alpine:3.23

RUN apk add --no-cache ca-certificates coreutils curl

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/local/bin/rustfs /usr/bin/rustfs
COPY --from=builder /usr/src/rustfs/entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/bin/rustfs /entrypoint.sh

RUN addgroup -g 10001 -S rustfs && \
    adduser -u 10001 -G rustfs -S rustfs -D && \
    mkdir -p /data /logs && \
    chown -R rustfs:rustfs /data /logs && \
    chmod 0750 /data /logs

ENV RUSTFS_ADDRESS=":9000" \
    RUSTFS_CONSOLE_ADDRESS=":9001" \
    RUSTFS_ACCESS_KEY="rustfsadmin" \
    RUSTFS_SECRET_KEY="rustfsadmin" \
    RUSTFS_CONSOLE_ENABLE="true" \
    RUSTFS_CORS_ALLOWED_ORIGINS="*" \
    RUSTFS_CONSOLE_CORS_ALLOWED_ORIGINS="*" \
    RUSTFS_VOLUMES="/data" \
    RUSTFS_OBS_LOGGER_LEVEL=warn \
    RUSTFS_OBS_LOG_DIRECTORY=/logs \
    RUSTFS_OBS_ENVIRONMENT=production

EXPOSE 9000 9001

VOLUME ["/data"]

USER rustfs

ENTRYPOINT ["/entrypoint.sh"]

CMD ["rustfs"]
