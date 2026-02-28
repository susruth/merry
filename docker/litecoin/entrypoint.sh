#!/usr/bin/env bash
set -euo pipefail

LITECOIN_DATADIR="/data/litecoin"
ELECTRS_DATADIR="/data/electrs"

echo "Starting litecoind in regtest mode..."
litecoind \
    -regtest \
    -server \
    -txindex \
    -datadir="${LITECOIN_DATADIR}" \
    -rpcuser=user \
    -rpcpassword=password \
    -rpcallowip=0.0.0.0/0 \
    -rpcbind=0.0.0.0 \
    -fallbackfee=0.00001 \
    -zmqpubrawblock=tcp://0.0.0.0:28332 \
    -zmqpubrawtx=tcp://0.0.0.0:28333 \
    -printtoconsole \
    -daemon

echo "Waiting for litecoind to be ready..."
LTC_CLI="litecoin-cli -regtest -datadir=${LITECOIN_DATADIR} -rpcuser=user -rpcpassword=password"
until $LTC_CLI getblockchaininfo > /dev/null 2>&1; do
    sleep 0.5
done
echo "litecoind is ready."

# Create or load wallet
$LTC_CLI createwallet "default" > /dev/null 2>&1 || $LTC_CLI loadwallet "default" > /dev/null 2>&1 || true

# Generate initial blocks only if chain is fresh (no blocks mined yet)
BLOCK_COUNT=$($LTC_CLI getblockcount)
if [ "$BLOCK_COUNT" -le 0 ]; then
    echo "Generating initial blocks..."
    ADDR=$($LTC_CLI -rpcwallet=default getnewaddress)
    $LTC_CLI generatetoaddress 101 "$ADDR" > /dev/null
    echo "Initial blocks generated (101 blocks)."
else
    echo "Chain already has $BLOCK_COUNT blocks, skipping initial generation."
fi

echo "Starting electrs for Litecoin..."
export RUST_LOG=INFO
exec electrs \
    --network litecoinregtest \
    --daemon-dir "${LITECOIN_DATADIR}" \
    --daemon-rpc-addr 127.0.0.1:19443 \
    --cookie "user:password" \
    --db-dir "${ELECTRS_DATADIR}" \
    --electrum-rpc-addr 0.0.0.0:60401 \
    --http-addr 0.0.0.0:3000
