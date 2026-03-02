# ==============================================================================
# Stage 1: Build zcashd v6.1.0 from source (needs glibc for Rust toolchain)
# ==============================================================================
FROM debian:bookworm-slim AS zcash-builder

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    bsdmainutils \
    build-essential \
    cmake \
    curl \
    git \
    libtool \
    m4 \
    ncurses-dev \
    pkg-config \
    python3 \
    python3-zmq \
    unzip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v6.1.0 --depth 1 https://github.com/zcash/zcash.git /zcash-src

WORKDIR /zcash-src

RUN ./zcutil/build.sh -j$(nproc)

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    bash \
    curl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy zcashd binaries
COPY --from=zcash-builder /zcash-src/src/zcashd /usr/local/bin/
COPY --from=zcash-builder /zcash-src/src/zcash-cli /usr/local/bin/
COPY --from=zcash-builder /zcash-src/src/zcash-tx /usr/local/bin/

# Create data and config directories
RUN mkdir -p /data/zcash /etc/zcash

# Copy configuration file
COPY zcash.conf /etc/zcash/zcash.conf

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Regtest RPC
EXPOSE 18232
# Regtest P2P
EXPOSE 18233

ENTRYPOINT ["/entrypoint.sh"]
