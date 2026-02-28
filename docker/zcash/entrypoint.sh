#!/bin/sh
set -euo pipefail

ZCASH_DATADIR="/data/zcash"

# Ensure the data directory exists
mkdir -p "${ZCASH_DATADIR}"

# Copy config into the data directory if not already there
if [ ! -f "${ZCASH_DATADIR}/zcash.conf" ]; then
    cp /etc/zcash/zcash.conf "${ZCASH_DATADIR}/zcash.conf"
fi

echo "Starting zcashd in regtest mode..."
exec zcashd \
    -datadir="${ZCASH_DATADIR}" \
    -printtoconsole \
    "$@"
