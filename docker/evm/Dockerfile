# Stage 1: Build geth from source
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache gcc musl-dev linux-headers git make

WORKDIR /go-ethereum

RUN git clone --branch v1.14.12 --depth 1 https://github.com/ethereum/go-ethereum.git .

RUN go run build/ci.go install -static ./cmd/geth

# Stage 2: Lightweight runtime image
FROM alpine:latest

RUN apk add --no-cache ca-certificates

COPY --from=builder /go-ethereum/build/bin/geth /usr/local/bin/

EXPOSE 8545 8546 30303 30303/udp

ENTRYPOINT ["geth"]

CMD [ \
    "--dev", \
    "--http", \
    "--http.addr", "0.0.0.0", \
    "--http.port", "8545", \
    "--http.api", "eth,net,web3,personal,debug,txpool", \
    "--http.corsdomain", "*", \
    "--http.vhosts", "*", \
    "--ws", \
    "--ws.addr", "0.0.0.0", \
    "--ws.port", "8546", \
    "--ws.api", "eth,net,web3,personal,debug,txpool", \
    "--ws.origins", "*" \
]
