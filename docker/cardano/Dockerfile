# ==============================================================================
# Stage 1: Build cardano-node 10.1.4 from source
# ==============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    curl \
    g++ \
    git \
    libffi-dev \
    libgmp-dev \
    libncurses-dev \
    libssl-dev \
    libsystemd-dev \
    libtool \
    pkg-config \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install GHC 9.6.6 and Cabal 3.10.3.0 via ghcup
ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_GHC_VERSION=9.6.6 \
    BOOTSTRAP_HASKELL_CABAL_VERSION=3.10.3.0 \
    GHCUP_INSTALL_BASE_PREFIX=/opt
ENV PATH="/opt/.ghcup/bin:$PATH"

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh \
    && ghcup install ghc 9.6.6 && ghcup set ghc 9.6.6 \
    && ghcup install cabal 3.10.3.0 && ghcup set cabal 3.10.3.0 \
    && ghc --version \
    && cabal --version

# --------------------------------------------------------------------------
# Build libsodium from source (Cardano requires the fork with VRF support)
# --------------------------------------------------------------------------
WORKDIR /build
RUN git clone --depth 1 https://github.com/intersectmbo/libsodium.git /build/libsodium
WORKDIR /build/libsodium
RUN ./autogen.sh \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install

# --------------------------------------------------------------------------
# Build libsecp256k1 from source
# --------------------------------------------------------------------------
WORKDIR /build
RUN git clone --depth 1 --branch v0.3.2 https://github.com/bitcoin-core/secp256k1.git /build/secp256k1
WORKDIR /build/secp256k1
RUN ./autogen.sh \
    && ./configure --prefix=/usr/local --enable-module-schnorrsig --enable-experimental \
    && make -j$(nproc) \
    && make install

# --------------------------------------------------------------------------
# Build libblst from source
# --------------------------------------------------------------------------
WORKDIR /build
RUN git clone --depth 1 https://github.com/supranational/blst.git /build/blst
WORKDIR /build/blst
RUN ./build.sh \
    && cp libblst.a /usr/local/lib/ \
    && cp bindings/blst.h bindings/blst_aux.h /usr/local/include/

# Update the shared library cache
RUN ldconfig

# --------------------------------------------------------------------------
# Build cardano-node and cardano-cli
# --------------------------------------------------------------------------
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

WORKDIR /build
RUN git clone --depth 1 --branch 10.1.4 \
    https://github.com/IntersectMBO/cardano-node.git /build/cardano-node

WORKDIR /build/cardano-node

RUN cabal update

# Write cabal.project.local to point at the custom C libraries
RUN echo "package cardano-crypto-praos"  >  cabal.project.local \
    && echo "  flags: -external-libsodium-vrf" >> cabal.project.local

RUN cabal build all -j$(nproc) \
    && mkdir -p /opt/cardano/bin \
    && cp $(cabal list-bin cardano-node) /opt/cardano/bin/ \
    && cp $(cabal list-bin cardano-cli)  /opt/cardano/bin/

# Verify the binaries were produced
RUN /opt/cardano/bin/cardano-node --version \
    && /opt/cardano/bin/cardano-cli --version

# ==============================================================================
# Stage 2: Lean runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install only the runtime libraries needed to execute cardano-node
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    libffi8 \
    libgmp10 \
    libncurses6 \
    libnuma1 \
    libssl3 \
    libsystemd0 \
    libtinfo6 \
    netbase \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Copy custom shared libraries from the builder
COPY --from=builder /usr/local/lib/libsodium*  /usr/local/lib/
COPY --from=builder /usr/local/lib/libsecp256k1* /usr/local/lib/
COPY --from=builder /usr/local/lib/libblst*    /usr/local/lib/
RUN ldconfig

# Copy cardano binaries
COPY --from=builder /opt/cardano/bin/cardano-node /usr/local/bin/
COPY --from=builder /opt/cardano/bin/cardano-cli  /usr/local/bin/

# Ensure binaries are executable
RUN chmod +x /usr/local/bin/cardano-node /usr/local/bin/cardano-cli

# Create a non-root user and data directories
RUN useradd -m -s /bin/bash cardano \
    && mkdir -p /data/cardano /data/cardano/config /data/cardano/db \
    && chown -R cardano:cardano /data/cardano

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cardano node port
EXPOSE 3001
# EKG monitoring port
EXPOSE 12788

ENTRYPOINT ["/entrypoint.sh"]
