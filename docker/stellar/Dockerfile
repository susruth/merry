# ==============================================================================
# Stage 1: Build stellar-core from source
# ==============================================================================
FROM ubuntu:22.04 AS builder

ARG STELLAR_CORE_VERSION=v22.0.0

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
# clang (clang-14) and libc++ are from stock Ubuntu 22.04
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    bison \
    build-essential \
    clang \
    curl \
    flex \
    git \
    libc++-dev \
    libc++abi-dev \
    libpq-dev \
    libtool \
    libunwind-dev \
    parallel \
    pkg-config \
    sed \
    perl \
    && rm -rf /var/lib/apt/lists/*

# Clone stellar-core at the specified release tag
RUN git clone --branch ${STELLAR_CORE_VERSION} --single-branch \
    https://github.com/stellar/stellar-core.git /stellar-core-src

WORKDIR /stellar-core-src

# Initialize submodules (needed for vendored dependencies)
RUN git submodule init && git submodule update --recursive

# Install the Rust toolchain (required for Soroban / protocol 20+ components)
RUN ./install-rust.sh
ENV PATH="/root/.cargo/bin:${PATH}"

# Set up clang with libc++ for the build
ENV CC=clang
ENV CXX=clang++
ENV CFLAGS="-O3 -g1 -fno-omit-frame-pointer"
ENV CXXFLAGS="-O3 -g1 -fno-omit-frame-pointer -stdlib=libc++"

# Build stellar-core
RUN ./autogen.sh \
    && ./configure --enable-next-protocol-version-unsafe-for-production \
    && make -j$(nproc) \
    && make install DESTDIR=/opt/stellar-core

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install only the runtime libraries needed by stellar-core, plus PostgreSQL
RUN apt-get update && apt-get install -y \
    libc++1 \
    libc++abi1 \
    libpq5 \
    libunwind8 \
    postgresql-14 \
    && rm -rf /var/lib/apt/lists/*

# Copy stellar-core binary from the builder stage
COPY --from=builder /opt/stellar-core/usr/local/bin/stellar-core /usr/local/bin/stellar-core

# Create required directories
RUN mkdir -p /etc/stellar /data/buckets /var/log/postgresql \
    && chown postgres:postgres /var/log/postgresql

# Copy configuration and entrypoint
COPY stellar-core.cfg /etc/stellar/stellar-core.cfg
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Peer-to-peer protocol
EXPOSE 11625
# HTTP / admin API
EXPOSE 11626

ENTRYPOINT ["/entrypoint.sh"]
