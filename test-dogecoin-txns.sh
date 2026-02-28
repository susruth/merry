#!/usr/bin/env bash
# ==============================================================================
# test-dogecoin-txns.sh
#
# Creates 100 transactions on Dogecoin regtest across different types,
# mines them into blocks, waits for electrs to index, and validates each
# transaction against the electrs HTTP API.
#
# Transaction types:
#   1. P2PKH (standard)          ~30 txns
#   2. Multi-output (fan-out)    ~30 txns
#   3. OP_RETURN (data carrier)  ~20 txns
#   4. Multisig (P2SH 2-of-3)   ~20 txns
#
# Usage:
#   ./test-dogecoin-txns.sh
# ==============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DOGE_RPC="http://localhost:18332/"
ELECTRS_HTTP="http://localhost:3020"
RPC_AUTH="user:password"

TOTAL_TARGET=100

# Counts per type
N_P2PKH=30
N_MULTIOUTPUT=30
N_OPRETURN=20
N_MULTISIG=20

BATCH=25         # txns per mining batch
MINE_BATCH=1     # blocks to mine per batch

green()  { printf "\033[32m%s\033[0m" "$*"; }
red()    { printf "\033[31m%s\033[0m" "$*"; }
yellow() { printf "\033[33m%s\033[0m" "$*"; }
bold()   { printf "\033[1m%s\033[0m" "$*"; }

# ---------------------------------------------------------------------------
# Helper: JSON-RPC call
# ---------------------------------------------------------------------------
rpc() {
    local method="$1"
    shift
    local params="$*"
    curl -sf --user "$RPC_AUTH" \
        --data-binary "{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"$method\",\"params\":[$params]}" \
        -H 'Content-Type: text/plain' \
        "$DOGE_RPC"
}

rpc_result() {
    rpc "$@" | jq -r '.result'
}

# ---------------------------------------------------------------------------
# Generate blocks and return mining address
# ---------------------------------------------------------------------------
mine_blocks() {
    local count="${1:-1}"
    local addr
    addr=$(rpc_result getnewaddress)
    rpc_result generatetoaddress "$count, \"$addr\"" > /dev/null
}

# ---------------------------------------------------------------------------
# Wait for electrs to sync to a given block height
# ---------------------------------------------------------------------------
wait_electrs_sync() {
    local target="$1"
    local max_wait=120
    local waited=0
    while true; do
        local tip
        tip=$(curl -sf "$ELECTRS_HTTP/blocks/tip/height" 2>/dev/null || echo "0")
        if [ "$tip" -ge "$target" ] 2>/dev/null; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$max_wait" ]; then
            echo "ERROR: electrs did not sync to height $target within ${max_wait}s (stuck at $tip)"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
echo ""
bold "============================================================"
bold "  Dogecoin Transaction Test Suite"
bold "============================================================"
echo ""

echo -n "  Checking Dogecoin RPC...      "
if ! rpc_result getblockchaininfo > /dev/null 2>&1; then
    red "FAIL"; echo " (cannot reach Dogecoin RPC at $DOGE_RPC)"
    exit 1
fi
green "OK"; echo ""

echo -n "  Checking Electrs HTTP...      "
if ! curl -sf "$ELECTRS_HTTP/blocks/tip/height" > /dev/null 2>&1; then
    red "FAIL"; echo " (cannot reach Electrs at $ELECTRS_HTTP)"
    exit 1
fi
green "OK"; echo ""

# ---------------------------------------------------------------------------
# Ensure enough mature balance -- mine more blocks if needed
# ---------------------------------------------------------------------------
echo -n "  Ensuring sufficient balance..."
BALANCE=$(rpc_result getbalance)
if (( $(echo "$BALANCE < 100000" | bc -l) )); then
    mine_blocks 200
    sleep 2
fi
BALANCE=$(rpc_result getbalance)
echo " $(green "$BALANCE DOGE")"
echo ""

INITIAL_HEIGHT=$(rpc_result getblockcount)

# ---------------------------------------------------------------------------
# Arrays to collect txids for later validation
# ---------------------------------------------------------------------------
ALL_TXIDS=()
declare -A TX_TYPES  # txid -> type label

CREATED=0

# ---------------------------------------------------------------------------
# Phase helpers
# ---------------------------------------------------------------------------
phase_start() {
    echo ""
    bold "--- Phase: $1 ($2 txns) ---"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 1: P2PKH (standard) transactions
# ---------------------------------------------------------------------------
phase_start "P2PKH (standard)" $N_P2PKH

i=0
while [ $i -lt $N_P2PKH ]; do
    addr=$(rpc_result getnewaddress)
    txid=$(rpc_result sendtoaddress "\"$addr\", 10.0")
    if [ "$txid" != "null" ] && [ -n "$txid" ]; then
        ALL_TXIDS+=("$txid")
        TX_TYPES["$txid"]="p2pkh"
        CREATED=$((CREATED + 1))
        i=$((i + 1))
    else
        mine_blocks 1
        sleep 0.1
        continue
    fi

    if (( i % BATCH == 0 && i > 0 )); then
        mine_blocks $MINE_BATCH
        printf "    %d / %d sent (mined batch)\n" "$i" "$N_P2PKH"
    fi
done
mine_blocks $MINE_BATCH
printf "    %d / %d complete\n" "$N_P2PKH" "$N_P2PKH"

# ---------------------------------------------------------------------------
# Phase 2: Multi-output transactions (fan-out, 5 outputs each)
# ---------------------------------------------------------------------------
phase_start "Multi-output (fan-out)" $N_MULTIOUTPUT

i=0
while [ $i -lt $N_MULTIOUTPUT ]; do
    ADDRS_JSON="{"
    for j in $(seq 1 5); do
        local_addr=$(rpc_result getnewaddress)
        if [ $j -gt 1 ]; then ADDRS_JSON+=","; fi
        ADDRS_JSON+="\"$local_addr\":1.0"
    done
    ADDRS_JSON+="}"

    txid=$(rpc_result sendmany "\"\", $ADDRS_JSON")
    if [ "$txid" != "null" ] && [ -n "$txid" ]; then
        ALL_TXIDS+=("$txid")
        TX_TYPES["$txid"]="multi-output"
        CREATED=$((CREATED + 1))
        i=$((i + 1))
    else
        mine_blocks 1
        sleep 0.1
        continue
    fi

    if (( i % BATCH == 0 && i > 0 )); then
        mine_blocks $MINE_BATCH
        printf "    %d / %d sent (mined batch)\n" "$i" "$N_MULTIOUTPUT"
    fi
done
mine_blocks $MINE_BATCH
printf "    %d / %d complete\n" "$N_MULTIOUTPUT" "$N_MULTIOUTPUT"

# ---------------------------------------------------------------------------
# Phase 3: OP_RETURN (data carrier) transactions
# ---------------------------------------------------------------------------
phase_start "OP_RETURN (data carrier)" $N_OPRETURN

i=0
while [ $i -lt $N_OPRETURN ]; do
    DATA_HEX=$(printf "merry-doge-test-%06d" "$i" | xxd -p | tr -d '\n')
    UTXO=$(rpc "listunspent" "1, 9999999, [], true, {\"minimumAmount\": 1.0}" | jq -r '.result[0]')
    if [ "$UTXO" = "null" ] || [ -z "$UTXO" ]; then
        mine_blocks 5
        sleep 0.2
        continue
    fi

    UTXO_TXID=$(echo "$UTXO" | jq -r '.txid')
    UTXO_VOUT=$(echo "$UTXO" | jq -r '.vout')
    UTXO_AMOUNT=$(echo "$UTXO" | jq -r '.amount')

    CHANGE_ADDR=$(rpc_result getnewaddress)
    CHANGE_AMT=$(echo "$UTXO_AMOUNT - 1.0" | bc -l | xargs printf "%.8f")

    RAW=$(rpc_result createrawtransaction \
        "[{\"txid\":\"$UTXO_TXID\",\"vout\":$UTXO_VOUT}], {\"data\":\"$DATA_HEX\",\"$CHANGE_ADDR\":$CHANGE_AMT}")

    SIGNED=$(rpc signrawtransaction "\"$RAW\"" | jq -r '.result.hex')
    txid=$(rpc_result sendrawtransaction "\"$SIGNED\"")

    if [ "$txid" != "null" ] && [ -n "$txid" ]; then
        ALL_TXIDS+=("$txid")
        TX_TYPES["$txid"]="op_return"
        CREATED=$((CREATED + 1))
        i=$((i + 1))
    else
        mine_blocks 1
        sleep 0.1
        continue
    fi

    if (( i % BATCH == 0 && i > 0 )); then
        mine_blocks $MINE_BATCH
        printf "    %d / %d sent (mined batch)\n" "$i" "$N_OPRETURN"
    fi
done
mine_blocks $MINE_BATCH
printf "    %d / %d complete\n" "$N_OPRETURN" "$N_OPRETURN"

# ---------------------------------------------------------------------------
# Phase 4: Multisig (2-of-3 P2SH) transactions
# ---------------------------------------------------------------------------
phase_start "Multisig (2-of-3 P2SH)" $N_MULTISIG

# Pre-generate 3 keys for multisig
MSIG_KEY1=$(rpc_result getnewaddress)
MSIG_KEY2=$(rpc_result getnewaddress)
MSIG_KEY3=$(rpc_result getnewaddress)

# Get their pubkeys via validateaddress (Dogecoin v1.14 uses validateaddress not getaddressinfo)
MSIG_PUB1=$(rpc "validateaddress" "\"$MSIG_KEY1\"" | jq -r '.result.pubkey')
MSIG_PUB2=$(rpc "validateaddress" "\"$MSIG_KEY2\"" | jq -r '.result.pubkey')
MSIG_PUB3=$(rpc "validateaddress" "\"$MSIG_KEY3\"" | jq -r '.result.pubkey')

# Create 2-of-3 multisig address
MSIG_RESULT=$(rpc "addmultisigaddress" "2, [\"$MSIG_PUB1\",\"$MSIG_PUB2\",\"$MSIG_PUB3\"]")
MSIG_ADDR=$(echo "$MSIG_RESULT" | jq -r '.result')

i=0
while [ $i -lt $N_MULTISIG ]; do
    txid=$(rpc_result sendtoaddress "\"$MSIG_ADDR\", 10.0")
    if [ "$txid" != "null" ] && [ -n "$txid" ]; then
        ALL_TXIDS+=("$txid")
        TX_TYPES["$txid"]="multisig"
        CREATED=$((CREATED + 1))
        i=$((i + 1))
    else
        mine_blocks 1
        sleep 0.1
        continue
    fi

    if (( i % BATCH == 0 && i > 0 )); then
        mine_blocks $MINE_BATCH
        printf "    %d / %d sent (mined batch)\n" "$i" "$N_MULTISIG"
    fi
done
mine_blocks $MINE_BATCH
printf "    %d / %d complete\n" "$N_MULTISIG" "$N_MULTISIG"

# ---------------------------------------------------------------------------
# Final mining -- ensure everything is confirmed
# ---------------------------------------------------------------------------
echo ""
bold "--- Mining final blocks ---"
mine_blocks 10

FINAL_HEIGHT=$(rpc_result getblockcount)
TOTAL_BLOCKS=$((FINAL_HEIGHT - INITIAL_HEIGHT))
echo "  Mined $TOTAL_BLOCKS blocks (height $INITIAL_HEIGHT -> $FINAL_HEIGHT)"
echo "  Total transactions created: $CREATED"

# ---------------------------------------------------------------------------
# Wait for electrs to fully sync
# ---------------------------------------------------------------------------
echo ""
bold "--- Waiting for Electrs to sync ---"
wait_electrs_sync "$FINAL_HEIGHT"
ELECTRS_TIP=$(curl -sf "$ELECTRS_HTTP/blocks/tip/height")
echo "  Electrs synced to height: $ELECTRS_TIP"

# ---------------------------------------------------------------------------
# Validation against Electrs
# ---------------------------------------------------------------------------
echo ""
bold "============================================================"
bold "  Validating transactions against Electrs indexer"
bold "============================================================"
echo ""

PASS=0
FAIL=0
FAIL_TXIDS=()

TOTAL_TO_VALIDATE=${#ALL_TXIDS[@]}
echo "  Validating $TOTAL_TO_VALIDATE transactions..."
echo ""

validated=0

for txid in "${ALL_TXIDS[@]}"; do
    HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" "$ELECTRS_HTTP/tx/$txid" 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" = "200" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAIL_TXIDS+=("$txid (${TX_TYPES[$txid]}) HTTP=$HTTP_STATUS")
    fi

    validated=$((validated + 1))
    if (( validated % 50 == 0 )); then
        printf "    Validated %d / %d  (pass=%d fail=%d)\n" "$validated" "$TOTAL_TO_VALIDATE" "$PASS" "$FAIL"
    fi
done

# ---------------------------------------------------------------------------
# Detailed spot-checks: verify tx content from electrs matches dogecoind
# ---------------------------------------------------------------------------
echo ""
bold "--- Spot-checking tx content (50 random txns) ---"

SPOT_PASS=0
SPOT_FAIL=0
SPOT_COUNT=50

STEP=$(( TOTAL_TO_VALIDATE / SPOT_COUNT ))
if [ "$STEP" -lt 1 ]; then STEP=1; fi

for (( s=0; s < SPOT_COUNT && s*STEP < TOTAL_TO_VALIDATE; s++ )); do
    idx=$(( s * STEP ))
    txid="${ALL_TXIDS[$idx]}"
    tx_type="${TX_TYPES[$txid]}"

    ELECTRS_TX=$(curl -sf "$ELECTRS_HTTP/tx/$txid" 2>/dev/null || echo "")
    if [ -z "$ELECTRS_TX" ]; then
        SPOT_FAIL=$((SPOT_FAIL + 1))
        continue
    fi

    E_TXID=$(echo "$ELECTRS_TX" | jq -r '.txid // empty' 2>/dev/null)
    E_SIZE=$(echo "$ELECTRS_TX" | jq -r '.size // empty' 2>/dev/null)
    E_VOUT_COUNT=$(echo "$ELECTRS_TX" | jq '.vout | length' 2>/dev/null)
    E_VIN_COUNT=$(echo "$ELECTRS_TX" | jq '.vin | length' 2>/dev/null)
    E_CONFIRMED=$(echo "$ELECTRS_TX" | jq -r '.status.confirmed // empty' 2>/dev/null)

    if [ "$E_TXID" != "$txid" ]; then
        SPOT_FAIL=$((SPOT_FAIL + 1))
        echo "    FAIL [$tx_type] txid mismatch: expected $txid got $E_TXID"
        continue
    fi

    if [ "$E_CONFIRMED" != "true" ]; then
        SPOT_FAIL=$((SPOT_FAIL + 1))
        echo "    FAIL [$tx_type] $txid not confirmed in electrs"
        continue
    fi

    if [ -z "$E_SIZE" ] || [ "$E_SIZE" = "0" ]; then
        SPOT_FAIL=$((SPOT_FAIL + 1))
        echo "    FAIL [$tx_type] $txid has zero size"
        continue
    fi
    if [ -z "$E_VIN_COUNT" ] || [ "$E_VIN_COUNT" = "0" ]; then
        SPOT_FAIL=$((SPOT_FAIL + 1))
        echo "    FAIL [$tx_type] $txid has zero vin"
        continue
    fi
    if [ -z "$E_VOUT_COUNT" ] || [ "$E_VOUT_COUNT" = "0" ]; then
        SPOT_FAIL=$((SPOT_FAIL + 1))
        echo "    FAIL [$tx_type] $txid has zero vout"
        continue
    fi

    case "$tx_type" in
        multi-output)
            if [ "$E_VOUT_COUNT" -lt 5 ]; then
                SPOT_FAIL=$((SPOT_FAIL + 1))
                echo "    FAIL [multi-output] $txid expected >=5 vouts, got $E_VOUT_COUNT"
                continue
            fi
            ;;
        op_return)
            HAS_OPRETURN=$(echo "$ELECTRS_TX" | jq '[.vout[].scriptpubkey_type] | any(. == "op_return")' 2>/dev/null)
            if [ "$HAS_OPRETURN" != "true" ]; then
                SPOT_FAIL=$((SPOT_FAIL + 1))
                echo "    FAIL [op_return] $txid missing OP_RETURN output"
                continue
            fi
            ;;
    esac

    SPOT_PASS=$((SPOT_PASS + 1))
done

echo "  Spot-check: $SPOT_PASS pass, $SPOT_FAIL fail (out of $SPOT_COUNT)"

# ---------------------------------------------------------------------------
# Verify block-level consistency
# ---------------------------------------------------------------------------
echo ""
bold "--- Block-level consistency checks ---"

BLOCK_PASS=0
BLOCK_FAIL=0

for bh in $(shuf -i "$((INITIAL_HEIGHT + 1))-$FINAL_HEIGHT" -n 20); do
    BLOCK_HASH=$(curl -sf "$ELECTRS_HTTP/block-height/$bh" 2>/dev/null || echo "")
    if [ -z "$BLOCK_HASH" ]; then
        BLOCK_FAIL=$((BLOCK_FAIL + 1))
        echo "    FAIL: no block hash for height $bh"
        continue
    fi

    BLOCK_DATA=$(curl -sf "$ELECTRS_HTTP/block/$BLOCK_HASH" 2>/dev/null || echo "")
    if [ -z "$BLOCK_DATA" ]; then
        BLOCK_FAIL=$((BLOCK_FAIL + 1))
        echo "    FAIL: no block data for $BLOCK_HASH at height $bh"
        continue
    fi

    E_BH=$(echo "$BLOCK_DATA" | jq -r '.height' 2>/dev/null)
    E_TX_COUNT=$(echo "$BLOCK_DATA" | jq -r '.tx_count' 2>/dev/null)

    if [ "$E_BH" != "$bh" ]; then
        BLOCK_FAIL=$((BLOCK_FAIL + 1))
        echo "    FAIL: height mismatch at $bh (electrs says $E_BH)"
        continue
    fi

    if [ -z "$E_TX_COUNT" ] || [ "$E_TX_COUNT" = "0" ]; then
        BLOCK_FAIL=$((BLOCK_FAIL + 1))
        echo "    FAIL: zero tx_count at height $bh"
        continue
    fi

    DOGE_HASH=$(rpc_result getblockhash "$bh")
    if [ "$BLOCK_HASH" != "$DOGE_HASH" ]; then
        BLOCK_FAIL=$((BLOCK_FAIL + 1))
        echo "    FAIL: block hash mismatch at $bh (electrs=$BLOCK_HASH doge=$DOGE_HASH)"
        continue
    fi

    BLOCK_PASS=$((BLOCK_PASS + 1))
done

echo "  Block checks: $BLOCK_PASS pass, $BLOCK_FAIL fail (out of 20)"

# ---------------------------------------------------------------------------
# Per-type summary
# ---------------------------------------------------------------------------
echo ""
bold "--- Per-type breakdown ---"

declare -A TYPE_COUNTS
for txid in "${ALL_TXIDS[@]}"; do
    t="${TX_TYPES[$txid]}"
    TYPE_COUNTS["$t"]=$(( ${TYPE_COUNTS["$t"]:-0} + 1 ))
done

for t in "${!TYPE_COUNTS[@]}"; do
    printf "  %-20s %d txns\n" "$t" "${TYPE_COUNTS[$t]}"
done

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
echo ""
bold "============================================================"
bold "  Final Results"
bold "============================================================"
echo ""
echo "  Transactions created:   $CREATED"
echo "  Blocks mined:           $TOTAL_BLOCKS  (height $INITIAL_HEIGHT -> $FINAL_HEIGHT)"
echo "  Electrs tip:            $ELECTRS_TIP"
echo ""
echo "  $(bold "TX indexing"):       $(green "PASS"): $PASS   $(red "FAIL"): $FAIL   (of $TOTAL_TO_VALIDATE)"
echo "  $(bold "Spot-checks"):      $(green "PASS"): $SPOT_PASS   $(red "FAIL"): $SPOT_FAIL   (of $SPOT_COUNT)"
echo "  $(bold "Block checks"):     $(green "PASS"): $BLOCK_PASS   $(red "FAIL"): $BLOCK_FAIL   (of 20)"
echo ""

TOTAL_FAIL=$((FAIL + SPOT_FAIL + BLOCK_FAIL))
if [ "$TOTAL_FAIL" -gt 0 ]; then
    red "Some tests failed!"; echo ""
    if [ ${#FAIL_TXIDS[@]} -gt 0 ]; then
        echo ""
        echo "  First 10 failed txids:"
        for ft in "${FAIL_TXIDS[@]:0:10}"; do
            echo "    - $ft"
        done
    fi
    exit 1
else
    green "All tests passed!"; echo ""
    exit 0
fi
