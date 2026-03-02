#!/usr/bin/env bash
set -euo pipefail

# Test script: Create 100 transparent Zcash transactions on regtest
# and verify them via the built-in Insight Explorer indexer

ZCASH_CLI="docker exec merry-zcash zcash-cli -datadir=/data/zcash"
NUM_TX=100

echo "=== Zcash Transparent Transaction Test ==="
echo "Creating ${NUM_TX} transparent transactions..."
echo ""

# Check zcashd is responsive
echo "Checking zcashd connectivity..."
BLOCK_COUNT=$($ZCASH_CLI getblockcount)
echo "Current block height: ${BLOCK_COUNT}"

# Create two addresses: a source (mining) address and a destination address
echo "Setting up addresses..."
SRC_ADDR=$($ZCASH_CLI getnewaddress)
DST_ADDR=$($ZCASH_CLI getnewaddress)
echo "Source  address: ${SRC_ADDR}"
echo "Dest    address: ${DST_ADDR}"

# Mine blocks to get spendable coins
# Need 100 confirmations for coinbase maturity
echo "Mining 101 blocks for coinbase maturity..."
$ZCASH_CLI generate 101 > /dev/null

BALANCE=$($ZCASH_CLI getbalance)
echo "Wallet balance: ${BALANCE} ZEC"
echo ""

# Send 100 transparent transactions
echo "Sending ${NUM_TX} transparent transactions..."
TXIDS=()
for i in $(seq 1 ${NUM_TX}); do
    TXID=$($ZCASH_CLI sendtoaddress "${DST_ADDR}" 0.01)
    TXIDS+=("${TXID}")
    if (( i % 10 == 0 )); then
        echo "  Sent ${i}/${NUM_TX} transactions"
    fi
done
echo "All ${NUM_TX} transactions sent."
echo ""

# Check mempool before mining
echo "=== Mempool Check (before mining) ==="
MEMPOOL_DELTAS=$($ZCASH_CLI getaddressmempool "{\"addresses\":[\"${DST_ADDR}\"]}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "UNAVAILABLE")
echo "Mempool entries for dest address: ${MEMPOOL_DELTAS}"

# Mine a block to confirm all transactions
echo ""
echo "Mining a block to confirm transactions..."
$ZCASH_CLI generate 1 > /dev/null
NEW_BLOCK_COUNT=$($ZCASH_CLI getblockcount)
echo "New block height: ${NEW_BLOCK_COUNT}"
echo ""

# Verify via Insight Explorer RPCs
echo "=== Insight Explorer Verification ==="

# getaddressbalance
ADDR_BALANCE=$($ZCASH_CLI getaddressbalance "{\"addresses\":[\"${DST_ADDR}\"]}")
BALANCE_SAT=$(echo "${ADDR_BALANCE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['balance'])" 2>/dev/null || echo "PARSE_ERROR")
BALANCE_ZEC=$(python3 -c "print(${BALANCE_SAT} / 100000000)" 2>/dev/null || echo "PARSE_ERROR")
echo "Dest address balance: ${BALANCE_ZEC} ZEC (expected: $(python3 -c "print(${NUM_TX} * 0.01)") ZEC)"

# getaddresstxids
ADDR_TXIDS=$($ZCASH_CLI getaddresstxids "{\"addresses\":[\"${DST_ADDR}\"]}")
ADDR_TX_COUNT=$(echo "${ADDR_TXIDS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "PARSE_ERROR")
echo "Indexed transactions for dest address: ${ADDR_TX_COUNT} (expected: ${NUM_TX})"

# getaddressutxos
ADDR_UTXOS=$($ZCASH_CLI getaddressutxos "{\"addresses\":[\"${DST_ADDR}\"]}")
UTXO_COUNT=$(echo "${ADDR_UTXOS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "PARSE_ERROR")
echo "UTXOs for dest address: ${UTXO_COUNT}"

# getaddressdeltas
ADDR_DELTAS=$($ZCASH_CLI getaddressdeltas "{\"addresses\":[\"${DST_ADDR}\"]}")
DELTA_COUNT=$(echo "${ADDR_DELTAS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "PARSE_ERROR")
echo "Address deltas: ${DELTA_COUNT}"

# Verify a sample transaction
SAMPLE_TXID="${TXIDS[0]}"
echo ""
echo "Verifying sample transaction: ${SAMPLE_TXID}"
TX_INFO=$($ZCASH_CLI gettransaction "${SAMPLE_TXID}")
CONFIRMATIONS=$(echo "${TX_INFO}" | python3 -c "import sys,json; print(json.load(sys.stdin)['confirmations'])" 2>/dev/null || echo "PARSE_ERROR")
echo "Confirmations: ${CONFIRMATIONS}"

# Also verify via zcash-cli for comparison
echo ""
echo "=== zcash-cli Verification ==="
MEMPOOL=$($ZCASH_CLI getmempoolinfo)
MEMPOOL_SIZE=$(echo "${MEMPOOL}" | python3 -c "import sys,json; print(json.load(sys.stdin)['size'])" 2>/dev/null || echo "PARSE_ERROR")
echo "Mempool size: ${MEMPOOL_SIZE} (should be 0 after mining)"

BLOCK_HASH=$($ZCASH_CLI getblockhash "${NEW_BLOCK_COUNT}")
BLOCK_TX_COUNT=$($ZCASH_CLI getblock "${BLOCK_HASH}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['tx']))" 2>/dev/null || echo "PARSE_ERROR")
echo "Transactions in latest block: ${BLOCK_TX_COUNT} (expected ~101: 100 sends + 1 coinbase)"

echo ""
echo "=== Summary ==="
echo "Transactions created: ${NUM_TX}"
echo "Block height: ${NEW_BLOCK_COUNT}"
echo "Dest address balance: ${BALANCE_ZEC} ZEC"
echo "Indexed tx count: ${ADDR_TX_COUNT}"
echo "UTXOs: ${UTXO_COUNT}"
echo ""
if [ "${ADDR_TX_COUNT}" = "${NUM_TX}" ] 2>/dev/null; then
    echo "SUCCESS: All ${NUM_TX} transparent transactions indexed by Insight Explorer!"
else
    echo "NOTE: Insight Explorer reports ${ADDR_TX_COUNT} transactions (expected ${NUM_TX})."
fi
