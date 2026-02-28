#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# entrypoint.sh -- Generate genesis files and start a Cardano local devnet
#
# This script creates a single-node private testnet that boots in Byron era
# and immediately hard-forks through every era up to Conway, so the node
# produces blocks from the moment it starts.
# ---------------------------------------------------------------------------
set -euo pipefail

# ----- Configurable paths ---------------------------------------------------
DATA_DIR="${DATA_DIR:-/data/cardano}"
CONFIG_DIR="${DATA_DIR}/config"
DB_DIR="${DATA_DIR}/db"
SOCKET_DIR="${DATA_DIR}/socket"
KEYS_DIR="${DATA_DIR}/keys"
SOCKET_PATH="${SOCKET_DIR}/node.socket"
NETWORK_MAGIC="${NETWORK_MAGIC:-42}"

export CARDANO_NODE_SOCKET_PATH="${SOCKET_PATH}"

# ----- Helper ---------------------------------------------------------------
log() { echo "[entrypoint] $*"; }

# ----- Skip generation if config already exists -----------------------------
if { [ -f "${CONFIG_DIR}/config.json" ] || [ -f "${CONFIG_DIR}/node-config.json" ]; } && [ -f "${CONFIG_DIR}/byron-genesis.json" ]; then
    log "Existing configuration found in ${CONFIG_DIR}, skipping genesis generation."
    # Ensure we have config.json (not node-config.json) for consistency
    if [ -f "${CONFIG_DIR}/node-config.json" ] && [ ! -f "${CONFIG_DIR}/config.json" ]; then
        mv "${CONFIG_DIR}/node-config.json" "${CONFIG_DIR}/config.json"
    fi
else
    log "Generating local devnet genesis (testnet-magic=${NETWORK_MAGIC})..."

    mkdir -p "${CONFIG_DIR}" "${DB_DIR}" "${SOCKET_DIR}" "${KEYS_DIR}"

    # -------------------------------------------------------------------
    # 1. Write the Byron genesis template
    # -------------------------------------------------------------------
    cat > "${CONFIG_DIR}/byron-template.json" <<'BYRON_EOF'
{
  "heavyDelThd": "300000000000",
  "maxBlockSize": "2000000",
  "maxTxSize": "4096",
  "maxHeaderSize": "2000000",
  "maxProposalSize": "700",
  "mpcThd": "20000000000000",
  "scriptVersion": 0,
  "slotDuration": "1000",
  "softforkRule": {
    "initThd": "900000000000000",
    "minThd": "600000000000000",
    "thdDecrement": "50000000000000"
  },
  "txFeePolicy": {
    "multiplier": "43946000000",
    "summand": "155381000000000"
  },
  "unlockStakeEpoch": "18446744073709551615",
  "updateImplicit": "10000",
  "updateProposalThd": "100000000000000",
  "updateVoteThd": "1000000000000"
}
BYRON_EOF

    # -------------------------------------------------------------------
    # 2. Write the Shelley genesis template
    # -------------------------------------------------------------------
    cat > "${CONFIG_DIR}/shelley-template.json" <<SHELLEY_EOF
{
  "activeSlotsCoeff": 0.05,
  "protocolParams": {
    "protocolVersion": { "minor": 0, "major": 8 },
    "decentralisationParam": 0,
    "eMax": 18,
    "extraEntropy": { "tag": "NeutralNonce" },
    "maxTxSize": 16384,
    "maxBlockBodySize": 65536,
    "maxBlockHeaderSize": 1100,
    "minFeeA": 44,
    "minFeeB": 155381,
    "minUTxOValue": 1000000,
    "poolDeposit": 500000000,
    "minPoolCost": 340000000,
    "keyDeposit": 2000000,
    "nOpt": 150,
    "rho": 0.003,
    "tau": 0.2,
    "a0": 0.3
  },
  "genDelegs": {},
  "updateQuorum": 1,
  "networkId": "Testnet",
  "initialFunds": {},
  "maxLovelaceSupply": 45000000000000000,
  "networkMagic": ${NETWORK_MAGIC},
  "epochLength": 500,
  "systemStart": "1970-01-01T00:00:00Z",
  "slotsPerKESPeriod": 129600,
  "slotLength": 0.2,
  "maxKESEvolutions": 62,
  "securityParam": 10
}
SHELLEY_EOF

    # -------------------------------------------------------------------
    # 3. Write the Alonzo genesis template
    # -------------------------------------------------------------------
    cat > "${CONFIG_DIR}/alonzo-template.json" <<'ALONZO_EOF'
{
  "lovelacePerUTxOWord": 34482,
  "executionPrices": {
    "prSteps": { "numerator": 721, "denominator": 10000000 },
    "prMem":   { "numerator": 577, "denominator": 10000 }
  },
  "maxTxExUnits":    { "exUnitsMem": 10000000000, "exUnitsSteps": 10000000000000 },
  "maxBlockExUnits": { "exUnitsMem": 50000000000, "exUnitsSteps": 40000000000000 },
  "maxValueSize": 5000,
  "collateralPercentage": 150,
  "maxCollateralInputs": 3,
  "costModels": {}
}
ALONZO_EOF

    # -------------------------------------------------------------------
    # 4. Write the Conway genesis template
    # -------------------------------------------------------------------
    cat > "${CONFIG_DIR}/conway-template.json" <<'CONWAY_EOF'
{
  "poolVotingThresholds": {
    "committeeNormal": 0.51,
    "committeeNoConfidence": 0.51,
    "hardForkInitiation": 0.51,
    "motionNoConfidence": 0.51,
    "ppSecurityGroup": 0.51
  },
  "dRepVotingThresholds": {
    "motionNoConfidence": 0.51,
    "committeeNormal": 0.51,
    "committeeNoConfidence": 0.51,
    "updateToConstitution": 0.51,
    "hardForkInitiation": 0.51,
    "ppNetworkGroup": 0.51,
    "ppEconomicGroup": 0.51,
    "ppTechnicalGroup": 0.51,
    "ppGovGroup": 0.51,
    "treasuryWithdrawal": 0.51
  },
  "committeeMinSize": 0,
  "committeeMaxTermLength": 200,
  "govActionLifetime": 10,
  "govActionDeposit": 1000000,
  "dRepDeposit": 500000000,
  "dRepActivity": 20,
  "minFeeRefScriptCostPerByte": 44,
  "constitution": {
    "anchor": {
      "url": "",
      "dataHash": "0000000000000000000000000000000000000000000000000000000000000000"
    }
  },
  "committee": {
    "members": {},
    "threshold": 0
  }
}
CONWAY_EOF

    # -------------------------------------------------------------------
    # 5. Write the node configuration template
    #    TestShelleyHardForkAtEpoch=0 causes an immediate hard-fork from
    #    Byron into Shelley at genesis. The same pattern continues through
    #    Allegra, Mary, Alonzo, Babbage, and Conway.
    # -------------------------------------------------------------------
    cat > "${CONFIG_DIR}/config-template.json" <<'CONFIG_EOF'
{
  "ApplicationName": "cardano-sl",
  "ApplicationVersion": 0,
  "ByronGenesisFile": "byron-genesis.json",
  "ShelleyGenesisFile": "shelley-genesis.json",
  "AlonzoGenesisFile": "alonzo-genesis.json",
  "ConwayGenesisFile": "conway-genesis.json",
  "Protocol": "Cardano",
  "RequiresNetworkMagic": "RequiresMagic",
  "LastKnownBlockVersion-Alt": 0,
  "LastKnownBlockVersion-Major": 3,
  "LastKnownBlockVersion-Minor": 1,
  "MaxKnownMajorProtocolVersion": 2,
  "PBftSignatureThreshold": 1.1,
  "TestShelleyHardForkAtEpoch": 0,
  "TestAllegraHardForkAtEpoch": 0,
  "TestMaryHardForkAtEpoch": 0,
  "TestAlonzoHardForkAtEpoch": 0,
  "TestBabbageHardForkAtEpoch": 0,
  "TestConwayHardForkAtEpoch": 0,
  "ExperimentalHardForksEnabled": true,
  "ExperimentalProtocolsEnabled": true,
  "EnableP2P": false,
  "TurnOnLogging": true,
  "TurnOnLogMetrics": true,
  "TraceBlockFetchDecisions": true,
  "TraceMempool": true,
  "minSeverity": "Info",
  "TracingVerbosity": "NormalVerbosity",
  "defaultBackends": ["KatipBK"],
  "setupBackends": ["KatipBK"],
  "defaultScribes": [["StdoutSK", "stdout"]],
  "setupScribes": [
    {
      "scFormat": "ScText",
      "scKind": "StdoutSK",
      "scName": "stdout",
      "scRotation": null
    }
  ],
  "options": {
    "mapBackends": {},
    "mapSubtrace": {
      "#ekgview": { "contents": [[ [{"contents":"cardano.epoch-validation.benchmark","tag":"Contains"},{"contents":".teleport","tag":"Contains"}],[{"tag":"StartMeasure"},{"contents":"","tag":"StopMeasure"}]],"tag":"TeeTrace" },
      "benchmark": { "contents": ["GhcRtsStats","MonotonicClock"],"tag":"ObservableTraceSelf" },
      "#messagecounters.aggregation": { "contents":"","tag":"NoTrace" },
      "#messagecounters.switchboard": { "contents":"","tag":"NoTrace" },
      "#messagecounters.katip": { "contents":"","tag":"NoTrace" },
      "#messagecounters.monitoring": { "contents":"","tag":"NoTrace" }
    }
  },
  "hasEKG": 12788,
  "hasPrometheus": ["0.0.0.0", 12798]
}
CONFIG_EOF

    # -------------------------------------------------------------------
    # 6. Generate genesis files using cardano-cli
    #    create-cardano produces Byron, Shelley, Alonzo, and Conway genesis
    #    files along with all necessary keys and delegation certificates.
    # -------------------------------------------------------------------
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cardano-cli legacy genesis create-cardano \
        --conway-era \
        --genesis-dir "${CONFIG_DIR}" \
        --gen-genesis-keys 1 \
        --gen-utxo-keys 1 \
        --supply 30000000000000000 \
        --testnet-magic "${NETWORK_MAGIC}" \
        --slot-length 1000 \
        --slot-coefficient 5/100 \
        --security-param 10 \
        --byron-template "${CONFIG_DIR}/byron-template.json" \
        --shelley-template "${CONFIG_DIR}/shelley-template.json" \
        --alonzo-template "${CONFIG_DIR}/alonzo-template.json" \
        --conway-template "${CONFIG_DIR}/conway-template.json" \
        --node-config-template "${CONFIG_DIR}/config-template.json"

    # -------------------------------------------------------------------
    # 7. Patch the generated configuration with the actual start time and
    #    correct genesis file paths.
    #    create-cardano outputs "node-config.json" from the template; we
    #    rename it to "config.json" for consistency.
    # -------------------------------------------------------------------
    if [ -f "${CONFIG_DIR}/node-config.json" ] && [ ! -f "${CONFIG_DIR}/config.json" ]; then
        mv "${CONFIG_DIR}/node-config.json" "${CONFIG_DIR}/config.json"
    fi

    # Update systemStart in shelley-genesis.json
    jq --arg t "${START_TIME}" '.systemStart = $t' \
        "${CONFIG_DIR}/shelley-genesis.json" > "${CONFIG_DIR}/shelley-genesis.json.tmp" \
        && mv "${CONFIG_DIR}/shelley-genesis.json.tmp" "${CONFIG_DIR}/shelley-genesis.json"

    # Compute and insert genesis hashes into config.json so the node
    # can verify integrity at startup
    BYRON_HASH=$(cardano-cli byron genesis print-genesis-hash \
        --genesis-json "${CONFIG_DIR}/byron-genesis.json")
    SHELLEY_HASH=$(cardano-cli legacy genesis hash \
        --genesis "${CONFIG_DIR}/shelley-genesis.json")
    ALONZO_HASH=$(cardano-cli legacy genesis hash \
        --genesis "${CONFIG_DIR}/alonzo-genesis.json")
    CONWAY_HASH=$(cardano-cli legacy genesis hash \
        --genesis "${CONFIG_DIR}/conway-genesis.json")

    jq --arg bh "${BYRON_HASH}" \
       --arg sh "${SHELLEY_HASH}" \
       --arg ah "${ALONZO_HASH}" \
       --arg ch "${CONWAY_HASH}" \
       '.ByronGenesisHash = $bh |
        .ShelleyGenesisHash = $sh |
        .AlonzoGenesisHash = $ah |
        .ConwayGenesisHash = $ch' \
        "${CONFIG_DIR}/config.json" > "${CONFIG_DIR}/config.json.tmp" \
        && mv "${CONFIG_DIR}/config.json.tmp" "${CONFIG_DIR}/config.json"

    # -------------------------------------------------------------------
    # 8. Create a simple topology file (standalone node, no peers)
    # -------------------------------------------------------------------
    cat > "${CONFIG_DIR}/topology.json" <<'TOPO_EOF'
{
  "Producers": []
}
TOPO_EOF

    log "Genesis generation complete."
    log "  Byron genesis hash:   ${BYRON_HASH}"
    log "  Shelley genesis hash: ${SHELLEY_HASH}"
    log "  Alonzo genesis hash:  ${ALONZO_HASH}"
    log "  Conway genesis hash:  ${CONWAY_HASH}"
    log "  Network magic:        ${NETWORK_MAGIC}"
    log "  Start time:           ${START_TIME}"
fi

# ---------------------------------------------------------------------------
# Find the delegation certificate and signing key for block production.
# These are created by create-cardano in the genesis-dir.
# ---------------------------------------------------------------------------
BYRON_DELEG_CERT=$(find "${CONFIG_DIR}" -path "*/delegate-keys/byron.000.cert.json" 2>/dev/null | head -1)
BYRON_SIGNING_KEY=$(find "${CONFIG_DIR}" -path "*/delegate-keys/byron.000.key" 2>/dev/null | head -1)
SHELLEY_KES_KEY=$(find "${CONFIG_DIR}" -path "*/delegate-keys/shelley.000.kes.skey" 2>/dev/null | head -1)
SHELLEY_VRF_KEY=$(find "${CONFIG_DIR}" -path "*/delegate-keys/shelley.000.vrf.skey" 2>/dev/null | head -1)
SHELLEY_OPCERT=$(find "${CONFIG_DIR}" -path "*/delegate-keys/shelley.000.opcert.json" 2>/dev/null | head -1)

# Build the block-production flags
DELEGATION_FLAGS=""
if [ -n "${BYRON_DELEG_CERT}" ] && [ -n "${BYRON_SIGNING_KEY}" ]; then
    DELEGATION_FLAGS="--delegation-certificate ${BYRON_DELEG_CERT} --signing-key ${BYRON_SIGNING_KEY}"
    log "Byron delegation: ${BYRON_DELEG_CERT}"
fi

SHELLEY_FLAGS=""
if [ -n "${SHELLEY_KES_KEY}" ] && [ -n "${SHELLEY_VRF_KEY}" ] && [ -n "${SHELLEY_OPCERT}" ]; then
    SHELLEY_FLAGS="--shelley-kes-key ${SHELLEY_KES_KEY} --shelley-vrf-key ${SHELLEY_VRF_KEY} --shelley-operational-certificate ${SHELLEY_OPCERT}"
    log "Shelley keys: KES=${SHELLEY_KES_KEY}, VRF=${SHELLEY_VRF_KEY}, OpCert=${SHELLEY_OPCERT}"
fi

# ---------------------------------------------------------------------------
# Start cardano-node
# ---------------------------------------------------------------------------
log "Starting cardano-node on local devnet (magic=${NETWORK_MAGIC}, port=3001)..."
exec cardano-node run \
    --topology "${CONFIG_DIR}/topology.json" \
    --database-path "${DB_DIR}" \
    --socket-path "${SOCKET_PATH}" \
    --config "${CONFIG_DIR}/config.json" \
    --host-addr 0.0.0.0 \
    --port 3001 \
    ${DELEGATION_FLAGS} \
    ${SHELLEY_FLAGS}
