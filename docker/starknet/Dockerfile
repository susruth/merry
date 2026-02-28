# ==============================================================================
# Stage 1: Build starknet-devnet from source
# ==============================================================================
FROM rust:1.85-alpine3.20 AS builder

RUN apk add --no-cache \
    build-base \
    git \
    openssl-dev \
    pkgconf \
    protobuf-dev

RUN git clone --branch v0.7.2 --depth 1 \
    https://github.com/0xSpaceShard/starknet-devnet-rs.git /starknet-devnet-rs

WORKDIR /starknet-devnet-rs

RUN cargo build --bin starknet-devnet --release

# ==============================================================================
# Stage 2: Runtime image
# ==============================================================================
FROM alpine:3.20

RUN apk add --no-cache \
    ca-certificates \
    libgcc \
    tini

COPY --from=builder /starknet-devnet-rs/target/release/starknet-devnet /usr/local/bin/starknet-devnet

EXPOSE 5050

ENTRYPOINT ["tini", "--", "starknet-devnet"]

CMD [ \
    "--host", "0.0.0.0", \
    "--port", "5050", \
    "--seed", "0" \
]
