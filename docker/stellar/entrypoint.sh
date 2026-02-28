#!/usr/bin/env bash
set -euo pipefail

echo "=== Stellar-core standalone localnet entrypoint ==="

# -------------------------------------------------------
# 1. Start PostgreSQL
# -------------------------------------------------------
echo "Starting PostgreSQL..."

PGDATA="/var/lib/postgresql/14/main"
PGBIN="/usr/lib/postgresql/14/bin"
PGLOG="/var/log/postgresql/postgresql.log"

# Initialize the data directory if it does not exist
if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "Initializing PostgreSQL data directory..."
    mkdir -p "$PGDATA"
    chown -R postgres:postgres "$PGDATA"
    su -s /bin/bash postgres -c "$PGBIN/initdb -D $PGDATA"
fi

# Allow local connections with password authentication
cat > "$PGDATA/pg_hba.conf" <<EOF
local   all   all                 trust
host    all   all   127.0.0.1/32  trust
host    all   all   ::1/128       trust
EOF

# Start PostgreSQL and wait for it to be ready
su -s /bin/bash postgres -c "$PGBIN/pg_ctl -D $PGDATA -l $PGLOG start -w"

echo "PostgreSQL started."

# -------------------------------------------------------
# 2. Create the database and user
# -------------------------------------------------------
echo "Creating stellar database and user..."

su -s /bin/bash postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='stellar'\" | grep -q 1 || psql -c \"CREATE USER stellar WITH PASSWORD 'stellar' CREATEDB;\""
su -s /bin/bash postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='stellar'\" | grep -q 1 || psql -c \"CREATE DATABASE stellar OWNER stellar;\""

echo "Database ready."

# -------------------------------------------------------
# 3. Initialize stellar-core database schema
# -------------------------------------------------------
echo "Initializing stellar-core database (new-db)..."
stellar-core new-db --conf /etc/stellar/stellar-core.cfg

echo "stellar-core database initialized."

# -------------------------------------------------------
# 4. Force SCP so the standalone node starts consensus
#    immediately without waiting for peers
# -------------------------------------------------------
echo "Setting force-scp flag..."
stellar-core force-scp --conf /etc/stellar/stellar-core.cfg

# -------------------------------------------------------
# 5. Start stellar-core
# -------------------------------------------------------
echo "Starting stellar-core run ..."
exec stellar-core run --conf /etc/stellar/stellar-core.cfg
