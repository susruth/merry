# ==============================================================================
# Stage 1: Build stellar-core from source
# ==============================================================================
FROM alpine:3.20 AS builder

ARG STELLAR_CORE_VERSION=v22.0.0

# Install build dependencies
RUN apk add --no-cache \
    autoconf \
    automake \
    bison \
    build-base \
    clang \
    clang-dev \
    curl \
    flex \
    git \
    libc++-dev \
    libpq-dev \
    libtool \
    libunwind-dev \
    parallel \
    perl \
    pkgconf

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
FROM alpine:3.20

# Install only the runtime libraries needed by stellar-core, plus PostgreSQL
RUN apk add --no-cache \
    bash \
    libc++ \
    libpq \
    libunwind \
    postgresql

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
