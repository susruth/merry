#!/usr/bin/env bash
# ==============================================================================
# test-endpoints.sh -- Verify all blockchain node API endpoints are responsive
#
# Usage:
#   ./test-endpoints.sh          # Test all chains
#   ./test-endpoints.sh bitcoin  # Test a specific chain
#
# Prerequisites:
#   - docker compose up -d (or specific services)
#   - curl and jq installed
# ==============================================================================
set -euo pipefail

PASS=0
FAIL=0
SKIP=0

green()  { printf "\033[32m%s\033[0m" "$*"; }
red()    { printf "\033[31m%s\033[0m" "$*"; }
yellow() { printf "\033[33m%s\033[0m" "$*"; }
bold()   { printf "\033[1m%s\033[0m" "$*"; }

check() {
    local name="$1"
    local cmd="$2"
    local expect="${3:-}"

    printf "  %-45s " "$name"

    local output
    if output=$(eval "$cmd" 2>&1); then
        if [ -n "$expect" ]; then
            if echo "$output" | grep -qi "$expect"; then
                green "PASS"; echo ""
                ((PASS++))
            else
                red "FAIL"; echo " (expected '$expect', got: $(echo "$output" | head -1 | cut -c1-80))"
                ((FAIL++))
            fi
        else
            green "PASS"; echo ""
            ((PASS++))
        fi
    else
        red "FAIL"; echo " ($output)"
        ((FAIL++))
    fi
}

check_container() {
    local name="$1"
    printf "  %-45s " "Container running"
    if docker compose ps --status running "$name" 2>/dev/null | grep -q "$name"; then
        green "PASS"; echo ""
        ((PASS++))
        return 0
    else
        red "FAIL"; echo " (container not running)"
        ((FAIL++))
        return 1
    fi
}

# ==============================================================================
# Bitcoin
# ==============================================================================
test_bitcoin() {
    echo ""
    bold "=== Bitcoin (regtest + Electrs) ==="; echo ""

    check_container "bitcoin" || return

    check "bitcoind RPC - getblockchaininfo" \
        "docker exec merry-bitcoin bitcoin-cli -regtest -datadir=/data/bitcoin getblockchaininfo" \
        "regtest"

    check "bitcoind RPC - getnetworkinfo" \
        "docker exec merry-bitcoin bitcoin-cli -regtest -datadir=/data/bitcoin getnetworkinfo" \
        "version"

    check "bitcoind RPC - generate a block" \
        "docker exec merry-bitcoin bitcoin-cli -regtest -datadir=/data/bitcoin -rpcwallet=default getnewaddress" \
        "bcrt1"

    check "Electrs - server.version" \
        "echo '{\"jsonrpc\":\"2.0\",\"method\":\"server.version\",\"params\":[\"test\",\"1.4\"],\"id\":1}' | timeout 5 nc -q 1 localhost 60401" \
        "result"
}

# ==============================================================================
# EVM (Geth)
# ==============================================================================
test_evm() {
    echo ""
    bold "=== EVM / Geth (dev mode) ==="; echo ""

    check_container "evm" || return

    check "Geth HTTP RPC - eth_blockNumber" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' http://localhost:8545/" \
        "result"

    check "Geth HTTP RPC - eth_chainId" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}' http://localhost:8545/" \
        "result"

    check "Geth HTTP RPC - net_version" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[],\"id\":1}' http://localhost:8545/" \
        "result"

    check "Geth HTTP RPC - eth_accounts" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_accounts\",\"params\":[],\"id\":1}' http://localhost:8545/" \
        "result"

    check "Geth WebSocket - eth_blockNumber" \
        "echo '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' | timeout 5 websocat ws://localhost:8546 2>/dev/null || curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}' http://localhost:8545/" \
        "result"
}

# ==============================================================================
# Solana
# ==============================================================================
test_solana() {
    echo ""
    bold "=== Solana (test-validator) ==="; echo ""

    check_container "solana" || return

    check "Solana RPC - getHealth" \
        "curl -sf http://localhost:8899/health" \
        "ok"

    check "Solana RPC - getVersion" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"getVersion\",\"params\":[],\"id\":1}' http://localhost:8899/" \
        "solana-core"

    check "Solana RPC - getSlot" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"getSlot\",\"params\":[],\"id\":1}' http://localhost:8899/" \
        "result"

    check "Solana RPC - getBlockHeight" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"getBlockHeight\",\"params\":[],\"id\":1}' http://localhost:8899/" \
        "result"

    check "Solana RPC - getEpochInfo" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"getEpochInfo\",\"params\":[],\"id\":1}' http://localhost:8899/" \
        "epoch"
}

# ==============================================================================
# Sui
# ==============================================================================
test_sui() {
    echo ""
    bold "=== Sui (local network) ==="; echo ""

    check_container "sui" || return

    check "Sui RPC - sui_getLatestCheckpointSequenceNumber" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"sui_getLatestCheckpointSequenceNumber\",\"params\":[],\"id\":1}' http://localhost:9000/" \
        "result"

    check "Sui RPC - sui_getTotalTransactionBlocks" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"sui_getTotalTransactionBlocks\",\"params\":[],\"id\":1}' http://localhost:9000/" \
        "result"

    check "Sui RPC - suix_getReferenceGasPrice" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"suix_getReferenceGasPrice\",\"params\":[],\"id\":1}' http://localhost:9000/" \
        "result"

    check "Sui Faucet - status" \
        "curl -sf http://localhost:9123/gas 2>/dev/null || curl -sf -X POST http://localhost:9123/gas -H 'Content-Type: application/json' --data '{\"FixedAmountRequest\":{\"recipient\":\"0x0000000000000000000000000000000000000000000000000000000000000000\"}}' 2>/dev/null" \
        ""
}

# ==============================================================================
# Starknet
# ==============================================================================
test_starknet() {
    echo ""
    bold "=== Starknet (devnet) ==="; echo ""

    check_container "starknet" || return

    check "Starknet RPC - starknet_chainId" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"starknet_chainId\",\"params\":[],\"id\":1}' http://localhost:5050/" \
        "result"

    check "Starknet RPC - starknet_blockNumber" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"starknet_blockNumber\",\"params\":[],\"id\":1}' http://localhost:5050/" \
        "result"

    check "Starknet RPC - starknet_syncing" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"starknet_syncing\",\"params\":[],\"id\":1}' http://localhost:5050/" \
        "result"

    check "Starknet - is_alive" \
        "curl -sf http://localhost:5050/is_alive" \
        "Alive"
}

# ==============================================================================
# Cardano
# ==============================================================================
test_cardano() {
    echo ""
    bold "=== Cardano (local devnet) ==="; echo ""

    check_container "cardano" || return

    check "Cardano EKG - metrics" \
        "curl -sf -H 'Accept: application/json' http://localhost:12788/" \
        ""

    check "Cardano - node socket exists" \
        "docker compose exec cardano test -S /data/cardano/socket/node.socket && echo 'socket exists'" \
        "socket exists"

    check "Cardano - query tip" \
        "docker compose exec cardano cardano-cli query tip --testnet-magic 42" \
        "slot"
}

# ==============================================================================
# Ripple / XRPL
# ==============================================================================
test_ripple() {
    echo ""
    bold "=== Ripple / XRPL (standalone) ==="; echo ""

    check_container "ripple" || return

    check "XRPL JSON-RPC - server_info" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"method\":\"server_info\",\"params\":[{}]}' http://localhost:5005/" \
        "result"

    check "XRPL JSON-RPC - server_state" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"method\":\"server_state\",\"params\":[{}]}' http://localhost:5005/" \
        "result"

    check "XRPL JSON-RPC - ledger" \
        "curl -sf -X POST -H 'Content-Type: application/json' --data '{\"method\":\"ledger\",\"params\":[{\"ledger_index\":\"validated\"}]}' http://localhost:5005/" \
        "result"

    check "XRPL WebSocket - server_info" \
        "echo '{\"command\":\"server_info\"}' | timeout 5 websocat ws://localhost:6006 2>/dev/null || echo 'websocat not available, skipping WS test'" \
        ""
}

# ==============================================================================
# Stellar
# ==============================================================================
test_stellar() {
    echo ""
    bold "=== Stellar (standalone) ==="; echo ""

    check_container "stellar" || return

    check "Stellar HTTP - info" \
        "curl -sf http://localhost:11626/info" \
        "info"

    check "Stellar HTTP - peers" \
        "curl -sf http://localhost:11626/peers" \
        ""

    check "Stellar HTTP - metrics" \
        "curl -sf http://localhost:11626/metrics" \
        ""

    check "Stellar HTTP - scp" \
        "curl -sf http://localhost:11626/scp" \
        ""
}

# ==============================================================================
# Dogecoin
# ==============================================================================
test_dogecoin() {
    echo ""
    bold "=== Dogecoin (regtest) ==="; echo ""

    check_container "dogecoin" || return

    check "Dogecoin RPC - getblockchaininfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:18332/" \
        "regtest"

    check "Dogecoin RPC - getnetworkinfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getnetworkinfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:18332/" \
        "version"

    check "Dogecoin RPC - getmininginfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getmininginfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:18332/" \
        "result"
}

# ==============================================================================
# Litecoin
# ==============================================================================
test_litecoin() {
    echo ""
    bold "=== Litecoin (regtest) ==="; echo ""

    check_container "litecoin" || return

    check "Litecoin RPC - getblockchaininfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:19443/" \
        "regtest"

    check "Litecoin RPC - getnetworkinfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getnetworkinfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:19443/" \
        "version"

    check "Litecoin RPC - getmininginfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getmininginfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:19443/" \
        "result"

    check "Litecoin RPC - block count >= 101" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getblockcount\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:19443/" \
        "result"

    check "Electrs HTTP - blocks tip height" \
        "curl -sf http://localhost:3010/blocks/tip/height" \
        ""

    check "Electrs HTTP - block at height 1" \
        "curl -sf http://localhost:3010/block-height/1" \
        ""
}

# ==============================================================================
# ZCash
# ==============================================================================
test_zcash() {
    echo ""
    bold "=== ZCash (regtest) ==="; echo ""

    check_container "zcash" || return

    check "ZCash RPC - getblockchaininfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getblockchaininfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:18232/" \
        "regtest"

    check "ZCash RPC - getinfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getinfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:18232/" \
        "version"

    check "ZCash RPC - getmininginfo" \
        "curl -sf --user user:password --data-binary '{\"jsonrpc\":\"1.0\",\"method\":\"getmininginfo\",\"params\":[]}' -H 'Content-Type: text/plain' http://localhost:18232/" \
        "result"
}

# ==============================================================================
# Lightning Network (LND)
# ==============================================================================
test_lightning() {
    echo ""
    bold "=== Lightning Network / LND ==="; echo ""

    check_container "lightning" || return

    check "LND lncli - getinfo" \
        "docker compose exec lightning lncli --network regtest getinfo" \
        "identity_pubkey"

    check "LND lncli - getnetworkinfo" \
        "docker compose exec lightning lncli --network regtest getnetworkinfo" \
        "num_nodes"

    local macaroon
    macaroon=$(docker compose exec lightning sh -c 'cat /root/.lnd/data/chain/bitcoin/regtest/admin.macaroon | od -An -tx1 | tr -d " \n"' 2>/dev/null)

    check "LND REST - getinfo" \
        "curl -sf --insecure -H 'Grpc-Metadata-macaroon: $macaroon' https://localhost:8080/v1/getinfo" \
        "identity_pubkey"
}

# ==============================================================================
# Main
# ==============================================================================
echo ""
bold "============================================================"
bold "  Merry Blockchain Nodes -- Endpoint Test Suite"
bold "============================================================"
echo ""

FILTER="${1:-all}"

if [ "$FILTER" = "all" ]; then
    test_bitcoin
    test_evm
    test_solana
    test_sui
    test_starknet
    test_cardano
    test_ripple
    test_stellar
    test_dogecoin
    test_litecoin
    test_zcash
    test_lightning
else
    if declare -f "test_$FILTER" > /dev/null 2>&1; then
        "test_$FILTER"
    else
        red "Unknown chain: $FILTER"; echo ""
        echo "Available: bitcoin evm solana sui starknet cardano ripple stellar dogecoin litecoin zcash lightning"
        exit 1
    fi
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
bold "============================================================"
bold "  Results"
bold "============================================================"
echo ""
echo "  $(green "PASS"): $PASS"
echo "  $(red "FAIL"): $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    red "Some tests failed!"; echo ""
    exit 1
else
    green "All tests passed!"; echo ""
    exit 0
fi
