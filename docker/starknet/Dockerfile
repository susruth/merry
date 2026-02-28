# ==============================================================================
# Stage 1: Build starknet-devnet from source
# ==============================================================================
FROM rust:1.85-slim-bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    libssl-dev \
    pkg-config \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v0.7.2 --depth 1 \
    https://github.com/0xSpaceShard/starknet-devnet-rs.git /starknet-devnet-rs

WORKDIR /starknet-devnet-rs

RUN cargo build --bin starknet-devnet --release

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates \
    tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /starknet-devnet-rs/target/release/starknet-devnet /usr/local/bin/starknet-devnet

EXPOSE 5050

ENTRYPOINT ["tini", "--", "starknet-devnet"]

CMD [ \
    "--host", "0.0.0.0", \
    "--port", "5050", \
    "--seed", "0" \
]
