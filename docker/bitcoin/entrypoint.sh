#!/bin/sh
set -euo pipefail

BITCOIN_DATADIR="/data/bitcoin"
ELECTRS_DATADIR="/data/electrs"

COOKIE_FILE="${BITCOIN_DATADIR}/regtest/.cookie"

echo "Starting bitcoind in regtest mode..."
bitcoind \
    -regtest \
    -server \
    -txindex \
    -datadir="${BITCOIN_DATADIR}" \
    -rpcauth='user:808f6bdd59239b10ba56d4edb15cf6c9$33ae97b541af1619eb0884d0568406691d3de16169eb8b434b7ba295a31c526c' \
    -rpcallowip=0.0.0.0/0 \
    -rpcbind=0.0.0.0 \
    -fallbackfee=0.00001 \
    -zmqpubrawblock=tcp://0.0.0.0:28332 \
    -zmqpubrawtx=tcp://0.0.0.0:28333 \
    -printtoconsole \
    -daemonwait

echo "Waiting for bitcoind to be ready..."
BTC_CLI="bitcoin-cli -regtest -datadir=${BITCOIN_DATADIR} -rpccookiefile=${COOKIE_FILE}"
until $BTC_CLI getblockchaininfo > /dev/null 2>&1; do
    sleep 0.5
done
echo "bitcoind is ready."

# Generate an initial block so bitcoind exits IBD mode
echo "Generating initial block..."
$BTC_CLI createwallet "default" > /dev/null 2>&1 || $BTC_CLI loadwallet "default" > /dev/null 2>&1 || true
ADDR=$($BTC_CLI -rpcwallet=default getnewaddress)
$BTC_CLI generatetoaddress 1 "$ADDR" > /dev/null
echo "Initial block generated."

echo "Starting electrs..."
exec electrs \
    --network regtest \
    --daemon-dir "${BITCOIN_DATADIR}" \
    --daemon-rpc-addr 127.0.0.1:18443 \
    --cookie-file "${COOKIE_FILE}" \
    --db-dir "${ELECTRS_DATADIR}" \
    --electrum-rpc-addr 0.0.0.0:60401 \
    --log-filters INFO
