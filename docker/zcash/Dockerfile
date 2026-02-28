# ==============================================================================
# Stage 1: Build zcashd v6.1.0 from source
# ==============================================================================
FROM alpine:3.20 AS zcash-builder

RUN apk add --no-cache \
    autoconf \
    automake \
    build-base \
    cmake \
    coreutils \
    curl \
    git \
    libtool \
    linux-headers \
    m4 \
    ncurses-dev \
    pkgconf \
    python3 \
    py3-zmq \
    unzip \
    zlib-dev

RUN git clone --branch v6.1.0 --depth 1 https://github.com/zcash/zcash.git /zcash-src

WORKDIR /zcash-src

RUN ./zcutil/build.sh -j$(nproc)

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    curl \
    libgcc \
    libgomp \
    libstdc++

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
