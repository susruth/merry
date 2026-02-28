#!/usr/bin/env bash
set -euo pipefail

CARDANO_DATA="/data/cardano"
CARDANO_CONFIG_DIR="${CARDANO_DATA}/config"
CARDANO_DB_DIR="${CARDANO_DATA}/db"
CARDANO_SOCKET="${CARDANO_DATA}/node.socket"

NETWORK="${CARDANO_NETWORK:-preview}"

# ------------------------------------------------------------------
# Generate default configuration files if they do not already exist
# ------------------------------------------------------------------
generate_config() {
    echo "Generating ${NETWORK} configuration files..."

    local BASE_URL="https://book.play.dev.cardano.org/environments/${NETWORK}"

    curl -sSL -o "${CARDANO_CONFIG_DIR}/config.json"           "${BASE_URL}/config.json"
    curl -sSL -o "${CARDANO_CONFIG_DIR}/topology.json"         "${BASE_URL}/topology.json"
    curl -sSL -o "${CARDANO_CONFIG_DIR}/byron-genesis.json"    "${BASE_URL}/byron-genesis.json"
    curl -sSL -o "${CARDANO_CONFIG_DIR}/shelley-genesis.json"  "${BASE_URL}/shelley-genesis.json"
    curl -sSL -o "${CARDANO_CONFIG_DIR}/alonzo-genesis.json"   "${BASE_URL}/alonzo-genesis.json"
    curl -sSL -o "${CARDANO_CONFIG_DIR}/conway-genesis.json"   "${BASE_URL}/conway-genesis.json"

    echo "Configuration files written to ${CARDANO_CONFIG_DIR}."
}

if [ ! -f "${CARDANO_CONFIG_DIR}/config.json" ]; then
    generate_config
else
    echo "Existing configuration found in ${CARDANO_CONFIG_DIR}, skipping generation."
fi

# ------------------------------------------------------------------
# Start cardano-node
# ------------------------------------------------------------------
echo "Starting cardano-node (${NETWORK})..."
exec cardano-node run \
    --topology "${CARDANO_CONFIG_DIR}/topology.json" \
    --database-path "${CARDANO_DB_DIR}" \
    --socket-path "${CARDANO_SOCKET}" \
    --config "${CARDANO_CONFIG_DIR}/config.json" \
    --host-addr 0.0.0.0 \
    --port 3001
