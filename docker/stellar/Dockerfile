# ==============================================================================
# Stage 1: Build stellar-core from source
# ==============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    bison \
    build-essential \
    clang \
    flex \
    git \
    libc++-dev \
    libc++abi-dev \
    libpq-dev \
    libtool \
    libunwind-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/stellar/stellar-core.git /stellar-core-src

WORKDIR /stellar-core-src

RUN git submodule init && git submodule update

RUN ./autogen.sh

RUN ./configure

RUN make -j$(nproc)

RUN make install DESTDIR=/opt/stellar-core

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    libc++1 \
    libc++abi1 \
    libpq5 \
    libunwind8 \
    postgresql-14 \
    && rm -rf /var/lib/apt/lists/*

# Copy stellar-core binaries from the builder stage
COPY --from=builder /opt/stellar-core/usr/local/bin/stellar-core /usr/local/bin/stellar-core

# Create required directories
RUN mkdir -p /etc/stellar /var/log/postgresql

# Ensure the PostgreSQL log directory is writable by the postgres user
RUN chown postgres:postgres /var/log/postgresql

# Copy configuration and entrypoint
COPY stellar-core.cfg /etc/stellar/stellar-core.cfg
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Peer-to-peer
EXPOSE 11625
# HTTP / admin
EXPOSE 11626

ENTRYPOINT ["/entrypoint.sh"]
