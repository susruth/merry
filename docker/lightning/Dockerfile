# ==============================================================================
# Stage 1: Build LND from source
# ==============================================================================
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache gcc musl-dev linux-headers git make

WORKDIR /lnd

RUN git clone --branch v0.18.4-beta --depth 1 https://github.com/lightningnetwork/lnd.git .

RUN make install tags="autopilotrpc chainrpc invoicesrpc routerrpc signrpc walletrpc watchtowerrpc wtclientrpc peersrpc"

# ==============================================================================
# Stage 2: Lightweight runtime image
# ==============================================================================
FROM alpine:latest

RUN apk add --no-cache ca-certificates

# Copy LND binaries from builder
COPY --from=builder /go/bin/lnd /usr/local/bin/
COPY --from=builder /go/bin/lncli /usr/local/bin/

# Create data and config directories
RUN mkdir -p /root/.lnd

# Copy configuration file
COPY lnd.conf /root/.lnd/lnd.conf

# P2P
EXPOSE 9735
# gRPC
EXPOSE 10009
# REST
EXPOSE 8080

ENTRYPOINT ["lnd"]
