# ==============================================================================
# Stage 1: Build cardano-node 10.1.4 from source
# ==============================================================================
# Building Cardano from source is extremely resource-intensive.
# Expect 45-90 minutes and 16GB+ RAM during compilation.

FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install all system build dependencies required by GHC, Cabal, and the
# native crypto libraries that Cardano depends on.
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    curl \
    g++ \
    git \
    jq \
    libffi-dev \
    libgmp-dev \
    libncurses-dev \
    libssl-dev \
    libsystemd-dev \
    libtool \
    make \
    pkg-config \
    wget \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install GHC 8.10.7 and Cabal 3.10.3.0 via ghcup
# cardano-node 10.1.4 defaults to compiler-nix-name = ghc8107
# (see nix/haskell.nix in the 10.1.4 tag)
# ---------------------------------------------------------------------------
ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    GHCUP_INSTALL_BASE_PREFIX=/opt
ENV PATH="/opt/.ghcup/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh \
    && ghcup install ghc 8.10.7 --set \
    && ghcup install cabal 3.10.3.0 --set \
    && ghc --version \
    && cabal --version

# ---------------------------------------------------------------------------
# Build libsodium from the Cardano/IOHK fork (specific commit for VRF support)
# Commit pinned from iohk-nix flake.lock for cardano-node 10.1.4
# ---------------------------------------------------------------------------
ENV SODIUM_COMMIT=dbb48cce5429cb6585c9034f002568964f1ce567

RUN git clone https://github.com/intersectmbo/libsodium.git /build/libsodium \
    && cd /build/libsodium \
    && git checkout ${SODIUM_COMMIT} \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install

# ---------------------------------------------------------------------------
# Build libsecp256k1 v0.3.2 (pinned from iohk-nix flake.lock)
# ---------------------------------------------------------------------------
ENV SECP256K1_VERSION=v0.3.2

RUN git clone --depth 1 --branch ${SECP256K1_VERSION} \
        https://github.com/bitcoin-core/secp256k1.git /build/secp256k1 \
    && cd /build/secp256k1 \
    && ./autogen.sh \
    && ./configure --prefix=/usr/local --enable-module-schnorrsig --enable-experimental \
    && make -j$(nproc) \
    && make install

# ---------------------------------------------------------------------------
# Build libblst v0.3.11 (pinned from iohk-nix flake.lock)
# ---------------------------------------------------------------------------
ENV BLST_VERSION=v0.3.11

RUN git clone --depth 1 --branch ${BLST_VERSION} \
        https://github.com/supranational/blst.git /build/blst \
    && cd /build/blst \
    && ./build.sh \
    && cp libblst.a /usr/local/lib/ \
    && cp bindings/blst.h bindings/blst.hpp bindings/blst_aux.h /usr/local/include/

# Refresh the shared library cache so the linker can find our libraries
RUN ldconfig

# ---------------------------------------------------------------------------
# Build cardano-node and cardano-cli from source
# ---------------------------------------------------------------------------
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}" \
    PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH}"

WORKDIR /build
RUN git clone --depth 1 --branch 10.1.4 \
    https://github.com/IntersectMBO/cardano-node.git /build/cardano-node

WORKDIR /build/cardano-node

# Tell cabal which compiler to use and enable the IOHK libsodium VRF fork
RUN echo "with-compiler: ghc-8.10.7" >> cabal.project.local \
    && echo ""                        >> cabal.project.local \
    && echo "package cardano-crypto-praos"    >> cabal.project.local \
    && echo "  flags: +external-libsodium-vrf" >> cabal.project.local

# Pull the package index (including CHaP for cardano-cli)
RUN cabal update

# Build cardano-node and cardano-cli.
# cardano-cli is pulled from CHaP (Cardano Haskell Packages) as a dependency
# of cardano-testnet which is part of this workspace.
RUN cabal build exe:cardano-node 2>&1 | tail -20
RUN cabal build exe:cardano-cli  2>&1 | tail -20

# Copy the binaries to a clean directory
RUN mkdir -p /opt/cardano/bin \
    && cp -p "$(cabal list-bin cardano-node)" /opt/cardano/bin/ \
    && cp -p "$(cabal list-bin cardano-cli)"  /opt/cardano/bin/ \
    && /opt/cardano/bin/cardano-node --version \
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
    libffi8ubuntu1 \
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
COPY --from=builder /usr/local/lib/libsodium*    /usr/local/lib/
COPY --from=builder /usr/local/lib/libsecp256k1* /usr/local/lib/
COPY --from=builder /usr/local/lib/libblst.a     /usr/local/lib/
RUN ldconfig

# Copy cardano binaries
COPY --from=builder /opt/cardano/bin/cardano-node /usr/local/bin/
COPY --from=builder /opt/cardano/bin/cardano-cli  /usr/local/bin/

# Ensure binaries are executable and functional
RUN chmod +x /usr/local/bin/cardano-node /usr/local/bin/cardano-cli \
    && cardano-node --version \
    && cardano-cli --version

# Create data directories
RUN mkdir -p /data/cardano/db \
             /data/cardano/config \
             /data/cardano/socket \
             /data/cardano/keys

# Environment variables for the local devnet
ENV CARDANO_NODE_SOCKET_PATH=/data/cardano/socket/node.socket \
    NETWORK_MAGIC=42 \
    DATA_DIR=/data/cardano

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cardano node port
EXPOSE 3001
# EKG monitoring port
EXPOSE 12788

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD test -S /data/cardano/socket/node.socket && cardano-cli ping -c 1 -h 127.0.0.1 -p 3001 -m ${NETWORK_MAGIC} 2>/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
