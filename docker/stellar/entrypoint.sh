#!/usr/bin/env bash
set -euo pipefail

echo "=== Stellar-core standalone localnet entrypoint ==="

# -------------------------------------------------------
# 1. Start PostgreSQL
# -------------------------------------------------------
echo "Starting PostgreSQL..."

# Ensure the PostgreSQL data directory is owned by the postgres user
if [ ! -f /var/lib/postgresql/14/main/PG_VERSION ]; then
    echo "Initializing PostgreSQL data directory..."
    su - postgres -c "/usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/14/main"
fi

# Start PostgreSQL service
su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/14/main -l /var/log/postgresql/postgresql.log start -w"

echo "PostgreSQL started."

# -------------------------------------------------------
# 2. Create the database and user
# -------------------------------------------------------
echo "Creating stellar database and user..."

# Create user and database if they don't exist
su - postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='stellar'\" | grep -q 1 || psql -c \"CREATE USER stellar WITH PASSWORD 'stellar' CREATEDB;\""
su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='stellar'\" | grep -q 1 || psql -c \"CREATE DATABASE stellar OWNER stellar;\""

echo "Database ready."

# -------------------------------------------------------
# 3. Initialize stellar-core database schema
# -------------------------------------------------------
echo "Initializing stellar-core database (new-db)..."
stellar-core new-db --conf /etc/stellar/stellar-core.cfg

echo "stellar-core database initialized."

# -------------------------------------------------------
# 4. Start stellar-core in standalone in-memory mode
# -------------------------------------------------------
echo "Starting stellar-core run --in-memory ..."
exec stellar-core run --in-memory --conf /etc/stellar/stellar-core.cfg
