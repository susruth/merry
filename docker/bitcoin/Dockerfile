# ==============================================================================
# Stage 1: Build Bitcoin Core v28.1 from source
# ==============================================================================
FROM ubuntu:22.04 AS bitcoin-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    git \
    libtool \
    pkg-config \
    python3 \
    libsqlite3-dev \
    libzmq3-dev \
    libevent-dev \
    libboost-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v28.1 --depth 1 https://github.com/bitcoin/bitcoin.git /bitcoin-src

WORKDIR /bitcoin-src

RUN ./autogen.sh

RUN ./configure \
    --disable-tests \
    --disable-bench \
    --disable-gui-tests \
    --without-gui \
    --with-zmq \
    --disable-wallet \
    --with-sqlite=yes \
    --prefix=/opt/bitcoin

RUN make -j$(nproc)
RUN make install

# ==============================================================================
# Stage 2: Build Electrs from source
# ==============================================================================
FROM ubuntu:22.04 AS electrs-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cargo \
    clang \
    cmake \
    git \
    rustc \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/romanz/electrs.git /electrs-src

WORKDIR /electrs-src

RUN cargo build --locked --release

# ==============================================================================
# Stage 3: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libevent-2.1-7 \
    libsqlite3-0 \
    libzmq5 \
    && rm -rf /var/lib/apt/lists/*

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
