# ==============================================================================
# Stage 1: Build Dogecoin Core v1.14.9 from source
# ==============================================================================
FROM ubuntu:22.04 AS dogecoin-builder

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
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v1.14.9 --depth 1 https://github.com/dogecoin/dogecoin.git /dogecoin-src

WORKDIR /dogecoin-src

RUN ./autogen.sh

RUN ./configure \
    --without-gui \
    --disable-tests \
    --disable-bench \
    --with-zmq \
    --prefix=/opt/dogecoin

RUN make -j$(nproc)
RUN make install

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libboost-chrono1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-program-options1.74.0 \
    libboost-system1.74.0 \
    libboost-thread1.74.0 \
    libdb5.3++ \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    libssl3 \
    libzmq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy Dogecoin Core binaries
COPY --from=dogecoin-builder /opt/dogecoin/bin/dogecoind /usr/local/bin/
COPY --from=dogecoin-builder /opt/dogecoin/bin/dogecoin-cli /usr/local/bin/

# Create data directory
RUN mkdir -p /data/dogecoin

# Regtest RPC
EXPOSE 18332
# Regtest P2P
EXPOSE 18444

ENTRYPOINT ["dogecoind"]

CMD [ \
    "-regtest", \
    "-server", \
    "-txindex", \
    "-datadir=/data/dogecoin", \
    "-rpcuser=user", \
    "-rpcpassword=password", \
    "-rpcallowip=0.0.0.0/0", \
    "-rpcbind=0.0.0.0", \
    "-fallbackfee=1.0", \
    "-printtoconsole", \
    "-nodebug" \
]
