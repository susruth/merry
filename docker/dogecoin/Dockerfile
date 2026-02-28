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
# Stage 2: Runtime image
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
