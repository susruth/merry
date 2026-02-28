# ==============================================================================
# Stage 1: Build Litecoin Core v0.21.4 from source
# ==============================================================================
FROM alpine:3.20 AS litecoin-builder

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
    python3 \
    zeromq-dev

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
FROM alpine:3.20

RUN apk add --no-cache \
    boost-filesystem \
    boost-thread \
    db \
    libevent \
    libssl3 \
    libstdc++ \
    zeromq

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
