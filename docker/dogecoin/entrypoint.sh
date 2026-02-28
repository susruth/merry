#!/usr/bin/env bash
set -euo pipefail

DOGECOIN_DATADIR="/data/dogecoin"
ELECTRS_DATADIR="/data/electrs"

echo "Starting dogecoind in regtest mode..."
dogecoind \
    -regtest \
    -server \
    -txindex \
    -datadir="${DOGECOIN_DATADIR}" \
    -rpcuser=user \
    -rpcpassword=password \
    -rpcallowip=0.0.0.0/0 \
    -rpcbind=0.0.0.0 \
    -fallbackfee=1.0 \
    -zmqpubrawblock=tcp://0.0.0.0:28332 \
    -zmqpubrawtx=tcp://0.0.0.0:28333 \
    -printtoconsole \
    -daemon

echo "Waiting for dogecoind to be ready..."
DOGE_CLI="dogecoin-cli -regtest -datadir=${DOGECOIN_DATADIR} -rpcuser=user -rpcpassword=password"
until $DOGE_CLI getblockchaininfo > /dev/null 2>&1; do
    sleep 0.5
done
echo "dogecoind is ready."

# Generate initial blocks only if chain is fresh (no blocks mined yet)
BLOCK_COUNT=$($DOGE_CLI getblockcount)
if [ "$BLOCK_COUNT" -le 0 ]; then
    echo "Generating initial blocks..."
    ADDR=$($DOGE_CLI getnewaddress)
    $DOGE_CLI generatetoaddress 101 "$ADDR" > /dev/null
    echo "Initial blocks generated (101 blocks)."
else
    echo "Chain already has $BLOCK_COUNT blocks, skipping initial generation."
fi

echo "Starting electrs for Dogecoin..."
export RUST_LOG=INFO
exec electrs \
    --network dogecoinregtest \
    --daemon-dir "${DOGECOIN_DATADIR}" \
    --daemon-rpc-addr 127.0.0.1:18332 \
    --cookie "user:password" \
    --db-dir "${ELECTRS_DATADIR}" \
    --electrum-rpc-addr 0.0.0.0:60401 \
    --http-addr 0.0.0.0:3000
