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
    fmt-dev \
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

RUN CXXFLAGS="-fpermissive" ./configure \
    --without-gui \
    --disable-tests \
    --disable-bench \
    --with-incompatible-bdb \
    --with-zmq \
    --prefix=/opt/litecoin

RUN make -j$(nproc) CXXFLAGS="-g -O2 -fpermissive"
RUN make install

# ==============================================================================
# Stage 2: Build Electrs (Litecoin) from source
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

RUN cargo build --release --features litecoin

# ==============================================================================
# Stage 3: Build Esplora frontend
# ==============================================================================
FROM node:20-alpine AS esplora-builder

RUN apk add --no-cache bash git

RUN git clone --depth 1 https://github.com/susruth/esplora.git /esplora-src

WORKDIR /esplora-src

SHELL ["/bin/bash", "-c"]
RUN npm install
RUN NATIVE_ASSET_LABEL=LTC SITE_TITLE="Litecoin Explorer" npm run dist

# ==============================================================================
# Stage 4: Runtime image
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    boost-filesystem \
    boost-thread \
    db \
    fmt \
    libevent \
    libssl3 \
    libstdc++ \
    nginx \
    zeromq

# Copy Litecoin Core binaries
COPY --from=litecoin-builder /opt/litecoin/bin/litecoind /usr/local/bin/
COPY --from=litecoin-builder /opt/litecoin/bin/litecoin-cli /usr/local/bin/

# Copy Electrs binary
COPY --from=electrs-builder /electrs-src/target/release/electrs /usr/local/bin/

# Copy Esplora frontend
COPY --from=esplora-builder /esplora-src/dist /srv/esplora

# Nginx config: serve esplora frontend and proxy /api to electrs
RUN mkdir -p /run/nginx && cat > /etc/nginx/http.d/default.conf <<'NGINX'
server {
    listen 5000 default_server;

    root /srv/esplora;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
    }

    location / {
        try_files $uri /index.html;
    }
}
NGINX

# Create data directories
RUN mkdir -p /data/litecoin /data/electrs

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Regtest RPC
EXPOSE 19443
# Regtest P2P
EXPOSE 19444
# Electrs RPC (electrum protocol)
EXPOSE 60401
# Electrs HTTP API
EXPOSE 3000
# Esplora Explorer
EXPOSE 5000

ENTRYPOINT ["/entrypoint.sh"]
