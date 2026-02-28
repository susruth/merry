# ==============================================================================
# Cardano local devnet node
#
# Uses the official pre-built nix-based image from IntersectMBO, adds jq
# (downloaded as a static binary), and layers our custom entrypoint for
# genesis generation and devnet startup.
# ==============================================================================

FROM ghcr.io/intersectmbo/cardano-node:10.1.4

# The official image is nix-based and has no package manager.
# Download jq as a static binary (needed by entrypoint for genesis patching).
ADD https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 /usr/local/bin/jq
RUN chmod +x /usr/local/bin/jq && jq --version

# Create data directories
RUN mkdir -p /data/cardano/db \
             /data/cardano/config \
             /data/cardano/socket \
             /data/cardano/keys

# Environment variables for the local devnet
ENV CARDANO_NODE_SOCKET_PATH=/data/cardano/socket/node.socket \
    NETWORK_MAGIC=42 \
    DATA_DIR=/data/cardano

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cardano node port
EXPOSE 3001
# EKG monitoring port
EXPOSE 12788

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD test -S /data/cardano/socket/node.socket && cardano-cli ping -c 1 -h 127.0.0.1 -p 3001 -m ${NETWORK_MAGIC} 2>/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
