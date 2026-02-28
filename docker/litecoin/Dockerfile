# ==============================================================================
# Stage 1: Build Litecoin Core v0.21.4 from source
# ==============================================================================
FROM ubuntu:22.04 AS litecoin-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    automake \
    autotools-dev \
    bsdmainutils \
    build-essential \
    git \
    libboost-all-dev \
    libdb5.3++-dev \
    libevent-dev \
    libssl-dev \
    libtool \
    libzmq3-dev \
    pkg-config \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v0.21.4 --depth 1 https://github.com/litecoin-project/litecoin.git /litecoin-src

WORKDIR /litecoin-src

RUN ./autogen.sh

RUN ./configure \
    --without-gui \
    --disable-tests \
    --disable-bench \
    --with-incompatible-bdb \
    --with-zmq \
    --prefix=/opt/litecoin

RUN make -j$(nproc)
RUN make install

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libboost-filesystem1.74.0 \
    libboost-thread1.74.0 \
    libdb5.3++ \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    libssl3 \
    libzmq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy Litecoin Core binaries
COPY --from=litecoin-builder /opt/litecoin/bin/litecoind /usr/local/bin/
COPY --from=litecoin-builder /opt/litecoin/bin/litecoin-cli /usr/local/bin/

# Create data directory
RUN mkdir -p /data/litecoin

# Regtest RPC
EXPOSE 19332
# Regtest P2P
EXPOSE 19444

ENTRYPOINT ["litecoind", \
    "-regtest", \
    "-server", \
    "-txindex", \
    "-datadir=/data/litecoin", \
    "-rpcuser=user", \
    "-rpcpassword=password", \
    "-rpcallowip=0.0.0.0/0", \
    "-rpcbind=0.0.0.0", \
    "-zmqpubrawblock=tcp://0.0.0.0:28332", \
    "-zmqpubrawtx=tcp://0.0.0.0:28333", \
    "-fallbackfee=0.00001", \
    "-printtoconsole"]
