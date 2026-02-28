#!/usr/bin/env bash
set -euo pipefail

BITCOIN_DATADIR="/data/bitcoin"
ELECTRS_DATADIR="/data/electrs"

echo "Starting bitcoind in regtest mode..."
bitcoind \
    -regtest \
    -server \
    -txindex \
    -datadir="${BITCOIN_DATADIR}" \
    -rpcuser=user \
    -rpcpassword=password \
    -rpcallowip=0.0.0.0/0 \
    -rpcbind=0.0.0.0 \
    -fallbackfee=0.00001 \
    -zmqpubrawblock=tcp://0.0.0.0:28332 \
    -zmqpubrawtx=tcp://0.0.0.0:28333 \
    -printtoconsole \
    -daemonwait

echo "Waiting for bitcoind to be ready..."
until bitcoin-cli \
    -regtest \
    -datadir="${BITCOIN_DATADIR}" \
    -rpcuser=user \
    -rpcpassword=password \
    getblockchaininfo > /dev/null 2>&1; do
    sleep 0.5
done
echo "bitcoind is ready."

echo "Starting electrs..."
exec electrs \
    --network regtest \
    --daemon-dir "${BITCOIN_DATADIR}" \
    --daemon-rpc-addr 127.0.0.1:18443 \
    --db-dir "${ELECTRS_DATADIR}" \
    --electrum-rpc-addr 0.0.0.0:60401 \
    --cookie user:password \
    --log-filters INFO
