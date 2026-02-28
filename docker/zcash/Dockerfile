# ==============================================================================
# Stage 1: Build zcashd v6.1.0 from source
# ==============================================================================
FROM ubuntu:20.04 AS zcash-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    bsdmainutils \
    build-essential \
    cmake \
    curl \
    g++-multilib \
    git \
    libc6-dev \
    libtool \
    m4 \
    ncurses-dev \
    pkg-config \
    python3 \
    unzip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v6.1.0 --depth 1 https://github.com/zcash/zcash.git /zcash-src

WORKDIR /zcash-src

RUN ./zcutil/build.sh -j$(nproc)

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy zcashd binaries
COPY --from=zcash-builder /zcash-src/src/zcashd /usr/local/bin/
COPY --from=zcash-builder /zcash-src/src/zcash-cli /usr/local/bin/

# Copy fetch-params script and run it to download Zcash parameters
COPY --from=zcash-builder /zcash-src/zcutil/fetch-params.sh /usr/local/bin/fetch-params.sh
RUN chmod +x /usr/local/bin/fetch-params.sh && /usr/local/bin/fetch-params.sh

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
