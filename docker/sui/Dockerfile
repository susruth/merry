# Build Sui from source and run a local network
# This is a multi-stage build to keep the final image small.
#
# NOTE: Building Sui from source is extremely resource-intensive.
# Expect 30+ minutes and 16GB+ RAM usage during compilation.

# ==============================================================================
# Stage 1: Build
# ==============================================================================
FROM alpine:3.20 AS builder

# Install all system dependencies required to compile Sui
RUN apk add --no-cache \
    build-base \
    clang-dev \
    cmake \
    curl \
    git \
    libpq-dev \
    llvm \
    openssl-dev \
    pkgconf \
    protobuf-dev \
    zlib-dev

# Install Rust via rustup. The repo's rust-toolchain.toml will override
# the default toolchain version if needed.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable \
    && rustc --version

# Clone the Sui repository at the testnet release tag
WORKDIR /build
RUN git clone --depth 1 --branch testnet-v1.39.3 https://github.com/MystenLabs/sui.git

WORKDIR /build/sui

# Build the sui binary in release mode.
# The sui binary includes all local network functionality (genesis, start, client, etc.)
RUN cargo build --release --bin sui

# Verify the binary was produced
RUN ls -lh target/release/sui && target/release/sui --version

# ==============================================================================
# Stage 2: Runtime
# ==============================================================================
FROM alpine:3.20

# Install only the runtime libraries needed to execute sui
RUN apk add --no-cache \
    ca-certificates \
    curl \
    libgcc \
    libpq \
    libssl3 \
    zlib

# Copy the compiled binary from the builder stage
COPY --from=builder /build/sui/target/release/sui /usr/local/bin/sui

# Ensure the binary is executable
RUN chmod +x /usr/local/bin/sui

# Create data directories
RUN mkdir -p /root/.sui/sui_config

# Copy the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose ports:
#   9000 - Fullnode JSON-RPC
#   9123 - Faucet
#   5003 - Additional fullnode / custom services
EXPOSE 9000 9123 5003

# Health check: query the RPC endpoint
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -sf -X POST http://localhost:9000 \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"sui_getLatestCheckpointSequenceNumber","id":1}' \
        || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
