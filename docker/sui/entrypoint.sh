#!/bin/bash
set -e

SUI_CONFIG_DIR="${SUI_CONFIG_DIR:-/root/.sui/sui_config}"
FORCE_REGENESIS="${FORCE_REGENESIS:-true}"
FULLNODE_RPC_PORT="${FULLNODE_RPC_PORT:-9000}"

if [ "$FORCE_REGENESIS" = "true" ]; then
    # In force-regenesis mode, sui start handles genesis automatically
    # and creates a fresh network on every startup. No persistent state.
    echo "Starting local Sui network (force-regenesis mode)..."
    exec sui start \
        --with-faucet \
        --force-regenesis \
        --fullnode-rpc-port "$FULLNODE_RPC_PORT"
else
    # In persistent mode, run genesis once on first startup, then
    # start the network preserving state across restarts.
    if [ ! -d "$SUI_CONFIG_DIR" ] || [ ! -f "$SUI_CONFIG_DIR/genesis.blob" ]; then
        echo "Running sui genesis (first start)..."
        sui genesis --working-dir "$SUI_CONFIG_DIR" --force
    fi
    echo "Starting local Sui network (persistent mode)..."
    exec sui start \
        --with-faucet \
        --network.config "$SUI_CONFIG_DIR" \
        --fullnode-rpc-port "$FULLNODE_RPC_PORT"
fi
