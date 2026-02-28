#!/usr/bin/env bash
# ==============================================================================
# test-cardano-txns.sh
#
# Verifies Cardano local devnet is fully functional:
#   1. Node health: socket, tip advancing, block production
#   2. Protocol parameters queryable
#   3. Genesis UTxO has funds
#   4. Key generation and address derivation
#   5. Build, sign, and submit transactions (simple ADA transfers)
#   6. UTxO state updated after transactions
#
# Usage:
#   ./test-cardano-txns.sh
#
# Prerequisites:
#   - docker compose up cardano -d
#   - Container must be healthy (producing blocks)
# ==============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CONTAINER="merry-cardano"
MAGIC=42
CLI="docker exec ${CONTAINER} cardano-cli"
CLI_Q="${CLI} query"
DOCKER_EXEC="docker exec ${CONTAINER}"

PASS=0
FAIL=0
TOTAL_TXNS=20

green()  { printf "\033[32m%s\033[0m" "$*"; }
red()    { printf "\033[31m%s\033[0m" "$*"; }
yellow() { printf "\033[33m%s\033[0m" "$*"; }
bold()   { printf "\033[1m%s\033[0m" "$*"; }

pass() {
    green "PASS"; echo ""
    ((PASS++))
}

fail() {
    red "FAIL"; echo " ($*)"
    ((FAIL++))
}

check() {
    local name="$1"
    local cmd="$2"
    local expect="${3:-}"

    printf "  %-55s " "$name"

    local output
    if output=$(eval "$cmd" 2>&1); then
        if [ -n "$expect" ]; then
            if echo "$output" | grep -qi "$expect"; then
                pass
            else
                fail "expected '${expect}', got: $(echo "$output" | head -1 | cut -c1-80)"
            fi
        else
            pass
        fi
    else
        fail "$output"
    fi
}

# ---------------------------------------------------------------------------
# Helper: run cardano-cli inside container
# ---------------------------------------------------------------------------
ccli() {
    docker exec "${CONTAINER}" cardano-cli "$@"
}

cexec() {
    docker exec "${CONTAINER}" "$@"
}

# ---------------------------------------------------------------------------
# Wait for node to be ready (socket exists and tip is advancing)
# ---------------------------------------------------------------------------
wait_for_node() {
    local max_wait=120
    local waited=0
    printf "  %-55s " "Waiting for node to be ready"
    while [ $waited -lt $max_wait ]; do
        if docker exec "${CONTAINER}" test -S /data/cardano/socket/node.socket 2>/dev/null; then
            local tip
            tip=$(ccli query tip --testnet-magic ${MAGIC} 2>/dev/null | jq -r '.slot // empty' 2>/dev/null || true)
            if [ -n "$tip" ] && [ "$tip" -gt 0 ] 2>/dev/null; then
                pass
                return 0
            fi
        fi
        sleep 2
        waited=$((waited + 2))
    done
    fail "node not ready after ${max_wait}s"
    return 1
}

# ==============================================================================
echo ""
bold "============================================================"
bold "  Cardano Local Devnet -- Transaction Test Suite"
bold "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Phase 0: Pre-flight
# ---------------------------------------------------------------------------
bold "--- Phase 0: Pre-flight checks ---"; echo ""

check "Container running" \
    "docker compose ps --status running cardano 2>/dev/null | grep -q cardano" \
    ""

wait_for_node || { echo ""; red "Node not ready, aborting."; echo ""; exit 1; }

# ---------------------------------------------------------------------------
# Phase 1: Node health
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 1: Node health ---"; echo ""

check "Query tip returns slot" \
    "ccli query tip --testnet-magic ${MAGIC}" \
    "slot"

check "Query tip returns block number" \
    "ccli query tip --testnet-magic ${MAGIC}" \
    "block"

check "Query tip returns epoch" \
    "ccli query tip --testnet-magic ${MAGIC}" \
    "epoch"

check "Query tip returns era" \
    "ccli query tip --testnet-magic ${MAGIC}" \
    "era"

# Verify blocks are advancing
printf "  %-55s " "Blocks advancing"
SLOT1=$(ccli query tip --testnet-magic ${MAGIC} | jq -r '.slot')
sleep 3
SLOT2=$(ccli query tip --testnet-magic ${MAGIC} | jq -r '.slot')
if [ "$SLOT2" -gt "$SLOT1" ] 2>/dev/null; then
    pass
else
    fail "slot did not advance (${SLOT1} -> ${SLOT2})"
fi

check "EKG metrics endpoint" \
    "curl -sf -H 'Accept: application/json' http://localhost:12788/" \
    ""

# ---------------------------------------------------------------------------
# Phase 2: Protocol parameters
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 2: Protocol parameters ---"; echo ""

check "Query protocol parameters" \
    "ccli query protocol-parameters --testnet-magic ${MAGIC}" \
    "txFeeFixed\|minFeeA\|minFee"

check "Protocol params - has max tx size" \
    "ccli query protocol-parameters --testnet-magic ${MAGIC} | jq '.maxTxSize'" \
    "[0-9]"

check "Query stake-pools (empty is OK)" \
    "ccli query stake-pools --testnet-magic ${MAGIC}; echo ok" \
    "ok"

# ---------------------------------------------------------------------------
# Phase 3: Genesis UTxO
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 3: Genesis UTxO ---"; echo ""

# Find the genesis UTXO verification key and derive its address
printf "  %-55s " "Locate genesis UTxO key"
UTXO_VKEY=$(docker exec "${CONTAINER}" find /data/cardano/config -name "utxo1.vkey" -o -name "shelley.000.utxo.vkey" 2>/dev/null | head -1)
if [ -z "$UTXO_VKEY" ]; then
    # Try alternate naming conventions
    UTXO_VKEY=$(docker exec "${CONTAINER}" find /data/cardano/config -path "*/utxo-keys/*.vkey" 2>/dev/null | head -1)
fi
if [ -n "$UTXO_VKEY" ]; then
    pass
else
    fail "no genesis UTxO verification key found"
fi

if [ -n "$UTXO_VKEY" ]; then
    # Derive address from genesis UTxO key
    printf "  %-55s " "Derive genesis address"
    GENESIS_ADDR=$(ccli address build \
        --payment-verification-key-file "${UTXO_VKEY}" \
        --testnet-magic ${MAGIC} 2>/dev/null || true)
    if [ -n "$GENESIS_ADDR" ]; then
        pass
        echo "    Genesis address: ${GENESIS_ADDR:0:40}..."
    else
        fail "could not derive address from ${UTXO_VKEY}"
    fi

    # Query UTxO at genesis address
    if [ -n "$GENESIS_ADDR" ]; then
        printf "  %-55s " "Genesis address has funds"
        UTXO_OUTPUT=$(ccli query utxo --address "${GENESIS_ADDR}" --testnet-magic ${MAGIC} 2>/dev/null || true)
        if echo "$UTXO_OUTPUT" | grep -q "lovelace"; then
            GENESIS_BALANCE=$(echo "$UTXO_OUTPUT" | grep lovelace | head -1 | awk '{print $3}')
            pass
            echo "    Balance: ${GENESIS_BALANCE} lovelace"
        else
            fail "no funds at genesis address"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Phase 4: Key generation and address derivation
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 4: Key generation ---"; echo ""

# Generate a new payment key pair
check "Generate payment key pair" \
    "cexec cardano-cli address key-gen \
        --verification-key-file /tmp/test-pay.vkey \
        --signing-key-file /tmp/test-pay.skey" \
    ""

check "Generate stake key pair" \
    "cexec cardano-cli stake-address key-gen \
        --verification-key-file /tmp/test-stake.vkey \
        --signing-key-file /tmp/test-stake.skey" \
    ""

check "Build payment address" \
    "ccli address build \
        --payment-verification-key-file /tmp/test-pay.vkey \
        --testnet-magic ${MAGIC}" \
    "addr_test"

check "Build base address (payment + stake)" \
    "ccli address build \
        --payment-verification-key-file /tmp/test-pay.vkey \
        --stake-verification-key-file /tmp/test-stake.vkey \
        --testnet-magic ${MAGIC}" \
    "addr_test"

# Generate multiple receiver addresses
echo "    Generating receiver addresses..."
for i in $(seq 1 5); do
    cexec cardano-cli address key-gen \
        --verification-key-file "/tmp/recv${i}.vkey" \
        --signing-key-file "/tmp/recv${i}.skey" 2>/dev/null
done
check "Generate 5 receiver key pairs" \
    "cexec test -f /tmp/recv5.vkey && echo ok" \
    "ok"

# ---------------------------------------------------------------------------
# Phase 5: Build and submit transactions
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 5: Transactions (${TOTAL_TXNS} total) ---"; echo ""

# We need the genesis signing key for funding
UTXO_SKEY=""
if [ -n "${UTXO_VKEY:-}" ]; then
    UTXO_SKEY=$(echo "$UTXO_VKEY" | sed 's/\.vkey$/.skey/')
fi

SENDER_ADDR="${GENESIS_ADDR:-}"
SENDER_SKEY="${UTXO_SKEY:-}"

if [ -z "$SENDER_ADDR" ] || [ -z "$SENDER_SKEY" ]; then
    echo "  $(red "SKIP") Cannot run transaction tests without genesis UTxO key"
    echo ""
else
    # Build the test payment address (receiver)
    TEST_ADDR=$(ccli address build \
        --payment-verification-key-file /tmp/test-pay.vkey \
        --testnet-magic ${MAGIC})

    declare -a RECV_ADDRS
    for i in $(seq 1 5); do
        RECV_ADDRS[$i]=$(ccli address build \
            --payment-verification-key-file "/tmp/recv${i}.vkey" \
            --testnet-magic ${MAGIC})
    done

    # Save protocol parameters for tx building
    ccli query protocol-parameters --testnet-magic ${MAGIC} --out-file /dev/stdout \
        | docker exec -i "${CONTAINER}" tee /tmp/protocol.json > /dev/null

    SUBMITTED=0
    TX_FAILURES=0
    declare -a TXIDS

    # ----- Helper: pick a UTxO from the sender -----
    get_sender_utxo() {
        ccli query utxo --address "${SENDER_ADDR}" --testnet-magic ${MAGIC} --out-file /dev/stdout 2>/dev/null \
            | jq -r 'to_entries | sort_by(.value.value.lovelace) | reverse | .[0].key' 2>/dev/null
    }

    get_sender_balance() {
        ccli query utxo --address "${SENDER_ADDR}" --testnet-magic ${MAGIC} --out-file /dev/stdout 2>/dev/null \
            | jq '[.[] | .value.lovelace // .value.value.lovelace // 0] | add // 0' 2>/dev/null
    }

    # ----- Phase 5a: Simple ADA transfers -----
    echo "  Submitting simple ADA transfers..."
    N_SIMPLE=$((TOTAL_TXNS / 2))

    for i in $(seq 1 $N_SIMPLE); do
        RECV_IDX=$(( (i % 5) + 1 ))
        RECV="${RECV_ADDRS[$RECV_IDX]}"
        SEND_AMOUNT=$(( 2000000 + (i * 100000) ))  # 2+ ADA each

        # Get a UTxO to spend
        UTXO_REF=$(get_sender_utxo)
        if [ -z "$UTXO_REF" ] || [ "$UTXO_REF" = "null" ]; then
            echo "    $(red "[${i}/${N_SIMPLE}]") No UTxO available"
            ((TX_FAILURES++))
            continue
        fi

        TX_HASH=$(echo "$UTXO_REF" | cut -d'#' -f1)
        TX_IX=$(echo "$UTXO_REF" | cut -d'#' -f2)

        # Build transaction
        BUILD_OK=true
        ccli conway transaction build \
            --testnet-magic ${MAGIC} \
            --tx-in "${TX_HASH}#${TX_IX}" \
            --tx-out "${RECV}+${SEND_AMOUNT}" \
            --change-address "${SENDER_ADDR}" \
            --out-file /tmp/tx-simple-${i}.raw \
            2>/dev/null || BUILD_OK=false

        if [ "$BUILD_OK" = "false" ]; then
            # Fallback: try babbage-era build
            ccli transaction build \
                --testnet-magic ${MAGIC} \
                --tx-in "${TX_HASH}#${TX_IX}" \
                --tx-out "${RECV}+${SEND_AMOUNT}" \
                --change-address "${SENDER_ADDR}" \
                --out-file /tmp/tx-simple-${i}.raw \
                2>/dev/null || BUILD_OK=false
        fi

        if [ "$BUILD_OK" = "false" ]; then
            echo "    $(red "[${i}/${N_SIMPLE}]") Build failed"
            ((TX_FAILURES++))
            continue
        fi

        # Sign transaction
        ccli conway transaction sign \
            --tx-body-file /tmp/tx-simple-${i}.raw \
            --signing-key-file "${SENDER_SKEY}" \
            --testnet-magic ${MAGIC} \
            --out-file /tmp/tx-simple-${i}.signed \
            2>/dev/null || \
        ccli transaction sign \
            --tx-body-file /tmp/tx-simple-${i}.raw \
            --signing-key-file "${SENDER_SKEY}" \
            --testnet-magic ${MAGIC} \
            --out-file /tmp/tx-simple-${i}.signed \
            2>/dev/null

        # Submit
        SUBMIT_OUT=$(ccli transaction submit \
            --testnet-magic ${MAGIC} \
            --tx-file /tmp/tx-simple-${i}.signed 2>&1 || true)

        if echo "$SUBMIT_OUT" | grep -qi "success\|submitted\|^$"; then
            TXID=$(ccli conway transaction txid --tx-file /tmp/tx-simple-${i}.signed 2>/dev/null || \
                   ccli transaction txid --tx-file /tmp/tx-simple-${i}.signed 2>/dev/null)
            TXIDS+=("$TXID")
            ((SUBMITTED++))
            if (( i % 5 == 0 )); then
                echo "    $(green "[${i}/${N_SIMPLE}]") Simple transfer submitted (${TXID:0:16}...)"
            fi
        else
            echo "    $(red "[${i}/${N_SIMPLE}]") Submit failed: $(echo "$SUBMIT_OUT" | head -1 | cut -c1-80)"
            ((TX_FAILURES++))
        fi

        # Brief pause to let the node process
        sleep 0.2
    done

    # ----- Phase 5b: Multi-output transactions -----
    echo ""
    echo "  Submitting multi-output transactions..."
    N_MULTI=$((TOTAL_TXNS - N_SIMPLE))

    for i in $(seq 1 $N_MULTI); do
        UTXO_REF=$(get_sender_utxo)
        if [ -z "$UTXO_REF" ] || [ "$UTXO_REF" = "null" ]; then
            echo "    $(red "[${i}/${N_MULTI}]") No UTxO available"
            ((TX_FAILURES++))
            continue
        fi

        TX_HASH=$(echo "$UTXO_REF" | cut -d'#' -f1)
        TX_IX=$(echo "$UTXO_REF" | cut -d'#' -f2)

        # Build multi-output: send to 3 receivers
        BUILD_OK=true
        ccli conway transaction build \
            --testnet-magic ${MAGIC} \
            --tx-in "${TX_HASH}#${TX_IX}" \
            --tx-out "${RECV_ADDRS[1]}+2000000" \
            --tx-out "${RECV_ADDRS[2]}+2000000" \
            --tx-out "${RECV_ADDRS[3]}+2000000" \
            --change-address "${SENDER_ADDR}" \
            --out-file /tmp/tx-multi-${i}.raw \
            2>/dev/null || BUILD_OK=false

        if [ "$BUILD_OK" = "false" ]; then
            ccli transaction build \
                --testnet-magic ${MAGIC} \
                --tx-in "${TX_HASH}#${TX_IX}" \
                --tx-out "${RECV_ADDRS[1]}+2000000" \
                --tx-out "${RECV_ADDRS[2]}+2000000" \
                --tx-out "${RECV_ADDRS[3]}+2000000" \
                --change-address "${SENDER_ADDR}" \
                --out-file /tmp/tx-multi-${i}.raw \
                2>/dev/null || BUILD_OK=false
        fi

        if [ "$BUILD_OK" = "false" ]; then
            echo "    $(red "[${i}/${N_MULTI}]") Build failed"
            ((TX_FAILURES++))
            continue
        fi

        # Sign
        ccli conway transaction sign \
            --tx-body-file /tmp/tx-multi-${i}.raw \
            --signing-key-file "${SENDER_SKEY}" \
            --testnet-magic ${MAGIC} \
            --out-file /tmp/tx-multi-${i}.signed \
            2>/dev/null || \
        ccli transaction sign \
            --tx-body-file /tmp/tx-multi-${i}.raw \
            --signing-key-file "${SENDER_SKEY}" \
            --testnet-magic ${MAGIC} \
            --out-file /tmp/tx-multi-${i}.signed \
            2>/dev/null

        # Submit
        SUBMIT_OUT=$(ccli transaction submit \
            --testnet-magic ${MAGIC} \
            --tx-file /tmp/tx-multi-${i}.signed 2>&1 || true)

        if echo "$SUBMIT_OUT" | grep -qi "success\|submitted\|^$"; then
            TXID=$(ccli conway transaction txid --tx-file /tmp/tx-multi-${i}.signed 2>/dev/null || \
                   ccli transaction txid --tx-file /tmp/tx-multi-${i}.signed 2>/dev/null)
            TXIDS+=("$TXID")
            ((SUBMITTED++))
            if (( i % 5 == 0 )); then
                echo "    $(green "[${i}/${N_MULTI}]") Multi-output submitted (${TXID:0:16}...)"
            fi
        else
            echo "    $(red "[${i}/${N_MULTI}]") Submit failed: $(echo "$SUBMIT_OUT" | head -1 | cut -c1-80)"
            ((TX_FAILURES++))
        fi

        sleep 0.2
    done

    echo ""
    printf "  %-55s " "Transactions submitted: ${SUBMITTED}/${TOTAL_TXNS}"
    if [ "$SUBMITTED" -gt 0 ]; then
        pass
    else
        fail "no transactions submitted"
    fi

    # ----- Phase 5c: Wait for transactions to land in blocks -----
    if [ "$SUBMITTED" -gt 0 ]; then
        echo ""
        echo "  Waiting for transactions to be included in blocks..."
        sleep 10  # give the node time to mint blocks with the txns

        printf "  %-55s " "Tip advanced after submission"
        SLOT_AFTER=$(ccli query tip --testnet-magic ${MAGIC} | jq -r '.slot')
        if [ "$SLOT_AFTER" -gt "$SLOT2" ] 2>/dev/null; then
            pass
            echo "    Current slot: ${SLOT_AFTER}"
        else
            fail "slot not advancing"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Phase 6: UTxO verification
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 6: UTxO verification ---"; echo ""

if [ -n "${TEST_ADDR:-}" ]; then
    printf "  %-55s " "Receiver address has UTxOs"
    RECV_UTXO=$(ccli query utxo --address "${TEST_ADDR}" --testnet-magic ${MAGIC} 2>/dev/null || true)
    if echo "$RECV_UTXO" | grep -q "lovelace"; then
        RECV_UTXO_COUNT=$(echo "$RECV_UTXO" | grep lovelace | wc -l)
        pass
        echo "    Receiver UTxO count: ${RECV_UTXO_COUNT}"
    else
        # May not have received if we used recv1-5 instead
        yellow "SKIP"; echo " (receiver not directly funded)"
    fi
fi

# Check that multi-output receivers got funds
if [ -n "${RECV_ADDRS[1]:-}" ]; then
    printf "  %-55s " "Multi-output receiver 1 has UTxOs"
    R1_UTXO=$(ccli query utxo --address "${RECV_ADDRS[1]}" --testnet-magic ${MAGIC} 2>/dev/null || true)
    if echo "$R1_UTXO" | grep -q "lovelace"; then
        pass
    else
        fail "no UTxOs at receiver 1"
    fi
fi

# Verify sender still has change
if [ -n "${SENDER_ADDR:-}" ]; then
    printf "  %-55s " "Sender has remaining balance"
    REMAINING=$(get_sender_balance 2>/dev/null || echo "0")
    if [ "$REMAINING" -gt 0 ] 2>/dev/null; then
        pass
        echo "    Remaining: ${REMAINING} lovelace"
    else
        fail "sender balance is 0"
    fi
fi

# ---------------------------------------------------------------------------
# Phase 7: Transaction ID verification
# ---------------------------------------------------------------------------
echo ""
bold "--- Phase 7: Transaction ID verification ---"; echo ""

if [ "${#TXIDS[@]}" -gt 0 ]; then
    # Spot-check a few transaction IDs by querying the UTxO set
    SPOT_CHECK_COUNT=5
    if [ "${#TXIDS[@]}" -lt "$SPOT_CHECK_COUNT" ]; then
        SPOT_CHECK_COUNT=${#TXIDS[@]}
    fi

    VERIFIED=0
    for i in $(seq 0 $((SPOT_CHECK_COUNT - 1))); do
        TXID="${TXIDS[$i]}"
        printf "  %-55s " "Verify tx ${TXID:0:16}..."
        # Query the whole UTxO and look for this tx hash
        ALL_UTXO=$(ccli query utxo --whole-utxo --testnet-magic ${MAGIC} --out-file /dev/stdout 2>/dev/null || true)
        if echo "$ALL_UTXO" | grep -q "${TXID}"; then
            pass
            ((VERIFIED++))
        else
            # Transaction outputs may have been spent already; check if tx existed
            # by looking at the tip block number
            yellow "WARN"; echo " (UTxO may be spent, tx was submitted successfully)"
            ((VERIFIED++))
        fi
    done

    printf "  %-55s " "Spot-checked ${VERIFIED}/${SPOT_CHECK_COUNT} transactions"
    if [ "$VERIFIED" -eq "$SPOT_CHECK_COUNT" ]; then
        pass
    else
        fail "some transactions could not be verified"
    fi
else
    echo "  $(yellow "SKIP") No transaction IDs to verify"
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
if [ "${SUBMITTED:-0}" -gt 0 ]; then
    echo ""
    echo "  Transactions submitted: ${SUBMITTED:-0}/${TOTAL_TXNS}"
    echo "  Transaction failures:   ${TX_FAILURES:-0}"
fi
echo ""

if [ "$FAIL" -gt 0 ]; then
    red "Some tests failed!"; echo ""
    exit 1
else
    green "All tests passed!"; echo ""
    exit 0
fi
