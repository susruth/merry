# ==============================================================================
# Stage 1: Build Bitcoin Core v28.1 from source
# ==============================================================================
FROM alpine:3.20 AS bitcoin-builder

RUN apk add --no-cache \
    autoconf \
    automake \
    boost-dev \
    build-base \
    git \
    libevent-dev \
    libtool \
    pkgconf \
    python3 \
    sqlite-dev \
    zeromq-dev

RUN git clone --branch v28.1 --depth 1 https://github.com/bitcoin/bitcoin.git /bitcoin-src

WORKDIR /bitcoin-src

RUN ./autogen.sh

RUN ./configure \
    --disable-tests \
    --disable-bench \
    --disable-gui-tests \
    --without-gui \
    --with-zmq \
    --with-sqlite=yes \
    --prefix=/opt/bitcoin

RUN make -j$(nproc)
RUN make install

# ==============================================================================
# Stage 2: Build Electrs from source
# ==============================================================================
FROM rust:1.82-alpine3.20 AS electrs-builder

RUN apk add --no-cache build-base clang-dev cmake git

RUN git clone --branch v0.10.6 --depth 1 https://github.com/romanz/electrs.git /electrs-src

WORKDIR /electrs-src

RUN cargo build --locked --release

# ==============================================================================
# Stage 3: Runtime image
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    libevent \
    libgcc \
    libstdc++ \
    sqlite-libs \
    zeromq

# Copy Bitcoin Core binaries
COPY --from=bitcoin-builder /opt/bitcoin/bin/bitcoind /usr/local/bin/
COPY --from=bitcoin-builder /opt/bitcoin/bin/bitcoin-cli /usr/local/bin/

# Copy Electrs binary
COPY --from=electrs-builder /electrs-src/target/release/electrs /usr/local/bin/

# Create data directories
RUN mkdir -p /data/bitcoin /data/electrs

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Regtest RPC
EXPOSE 18443
# Regtest P2P
EXPOSE 18444
# Electrs RPC (electrum protocol)
EXPOSE 60401
# ZMQ raw block
EXPOSE 28332
# ZMQ raw tx
EXPOSE 28333

ENTRYPOINT ["/entrypoint.sh"]
