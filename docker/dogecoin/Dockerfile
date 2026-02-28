# ==============================================================================
# Stage 1: Build Dogecoin Core v1.14.9 from source
# ==============================================================================
FROM alpine:3.20 AS dogecoin-builder

RUN apk add --no-cache \
    autoconf \
    automake \
    boost-dev \
    build-base \
    coreutils \
    db-dev \
    git \
    libevent-dev \
    libtool \
    openssl-dev \
    pkgconf \
    zeromq-dev

RUN git clone --branch v1.14.9 --depth 1 https://github.com/dogecoin/dogecoin.git /dogecoin-src

WORKDIR /dogecoin-src

RUN ./autogen.sh

RUN ./configure \
    --without-gui \
    --disable-tests \
    --disable-bench \
    --with-zmq \
    --with-incompatible-bdb \
    --prefix=/opt/dogecoin

RUN make -j$(nproc)
RUN make install

# ==============================================================================
# Stage 2: Build Electrs (Dogecoin) from source
# ==============================================================================
FROM rust:1.85-slim-bookworm AS electrs-builder

RUN apt-get update && apt-get install -y \
    clang \
    cmake \
    git \
    librocksdb-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch new-index --depth 1 https://github.com/susruth/electrs.git /electrs-src

WORKDIR /electrs-src

RUN cargo build --release --features dogecoin

# ==============================================================================
# Stage 3: Runtime image
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    boost-chrono \
    boost-filesystem \
    boost-program_options \
    boost-system \
    boost-thread \
    db \
    libevent \
    libssl3 \
    libstdc++ \
    zeromq

# Copy Dogecoin Core binaries
COPY --from=dogecoin-builder /opt/dogecoin/bin/dogecoind /usr/local/bin/
COPY --from=dogecoin-builder /opt/dogecoin/bin/dogecoin-cli /usr/local/bin/

# Copy Electrs binary
COPY --from=electrs-builder /electrs-src/target/release/electrs /usr/local/bin/

# Create data directories
RUN mkdir -p /data/dogecoin /data/electrs

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Regtest RPC
EXPOSE 18332
# Regtest P2P
EXPOSE 18444
# Electrs RPC (electrum protocol)
EXPOSE 60401
# Electrs HTTP API
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
