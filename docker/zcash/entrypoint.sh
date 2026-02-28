#!/usr/bin/env bash
set -euo pipefail

echo "Starting zcashd in regtest mode..."
exec zcashd -conf=/etc/zcash/zcash.conf -printtoconsole
