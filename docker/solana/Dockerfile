# Build Solana test-validator from source (Agave v2.1.7)
# This is a multi-stage build to keep the final image small.
#
# NOTE: Building Solana from source is extremely resource-intensive.
# Expect 30+ minutes and 16GB+ RAM usage during compilation.

# ==============================================================================
# Stage 1: Build
# ==============================================================================
FROM rust:1.81-alpine3.20 AS builder

# Install all system dependencies required to compile Solana/Agave
RUN apk add --no-cache \
    build-base \
    clang-dev \
    cmake \
    curl \
    eudev-dev \
    git \
    llvm \
    openssl-dev \
    pkgconf \
    protobuf-dev \
    zlib-dev

# Clone the Agave repository at the exact release tag
WORKDIR /build
RUN git clone --depth 1 --branch v2.1.7 https://github.com/anza-xyz/agave.git

WORKDIR /build/agave

# Build only the solana-test-validator binary in release mode.
# We target just this one binary to avoid building the entire workspace.
# CI=1 is set to match upstream CI behavior for reproducible builds.
ENV CI=1
RUN cargo build --release --bin solana-test-validator \
    && cargo build --release --bin solana-keygen \
    && cargo build --release --bin solana-faucet

# Verify the binaries were produced
RUN ls -lh target/release/solana-test-validator \
    && ls -lh target/release/solana-keygen \
    && ls -lh target/release/solana-faucet

# ==============================================================================
# Stage 2: Runtime
# ==============================================================================
FROM alpine:3.20

# Install only the runtime libraries needed to execute the validator
RUN apk add --no-cache \
    bzip2 \
    ca-certificates \
    curl \
    eudev-libs \
    libgcc \
    libssl3 \
    zlib

# Copy the compiled binaries from the builder stage
COPY --from=builder /build/agave/target/release/solana-test-validator /usr/local/bin/
COPY --from=builder /build/agave/target/release/solana-keygen /usr/local/bin/
COPY --from=builder /build/agave/target/release/solana-faucet /usr/local/bin/

# Ensure binaries are executable
RUN chmod +x /usr/local/bin/solana-test-validator \
    /usr/local/bin/solana-keygen \
    /usr/local/bin/solana-faucet

# Create a non-root user to run the validator
RUN adduser -D -s /bin/sh solana
USER solana
WORKDIR /home/solana

# Create the default ledger directory
RUN mkdir -p /home/solana/test-ledger

# Expose ports:
#   8899 - JSON-RPC
#   8900 - WebSocket (RPC pubsub)
#   9900 - Faucet
EXPOSE 8899 8900 9900

# Health check: query the RPC endpoint for version info
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD curl -sf http://localhost:8899/health || exit 1

# Start the test validator bound to all interfaces so it is accessible
# from outside the container. --reset clears any previous ledger state
# on each startup.
ENTRYPOINT ["solana-test-validator"]
CMD ["--reset", "--rpc-port", "8899", "--bind-address", "0.0.0.0", "--log"]
