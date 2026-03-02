#!/usr/bin/env bash
set -euo pipefail

ZCASH_DATADIR="/data/zcash"

# Ensure the data directory exists
mkdir -p "${ZCASH_DATADIR}"

# Copy config into the data directory if not already there
if [ ! -f "${ZCASH_DATADIR}/zcash.conf" ]; then
    cp /etc/zcash/zcash.conf "${ZCASH_DATADIR}/zcash.conf"
fi

echo "Starting zcashd in regtest mode..."
zcashd \
    -datadir="${ZCASH_DATADIR}" \
    -printtoconsole &
ZCASHD_PID=$!

echo "Waiting for zcashd to be ready..."
ZCASH_CLI="zcash-cli -datadir=${ZCASH_DATADIR}"
until $ZCASH_CLI getblockchaininfo > /dev/null 2>&1; do
    sleep 0.5
done
echo "zcashd is ready."

# Generate initial blocks only if chain is fresh (no blocks mined yet)
BLOCK_COUNT=$($ZCASH_CLI getblockcount)
if [ "$BLOCK_COUNT" -le 0 ]; then
    echo "Generating initial blocks..."
    $ZCASH_CLI generate 101 > /dev/null
    echo "Initial blocks generated (101 blocks)."
else
    echo "Chain already has $BLOCK_COUNT blocks, skipping initial generation."
fi

# Wait for zcashd (the main process)
wait $ZCASHD_PID
