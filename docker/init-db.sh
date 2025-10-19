#!/bin/bash
set -e

# This script initializes all databases and users for the homelab applications
# It runs automatically when the PostgreSQL container is first created

echo "Starting database initialization..."

# Function to create database and user
create_db_and_user() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3

    echo "Creating database: $db_name with user: $db_user"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        -- Create user if not exists
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$db_user') THEN
                CREATE USER $db_user WITH PASSWORD '$db_pass';
            END IF;
        END
        \$\$;

        -- Create database if not exists
        SELECT 'CREATE DATABASE $db_name OWNER $db_user'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db_name')\gexec

        -- Grant privileges
        GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;
EOSQL

    echo "✓ Database $db_name created successfully"
}

# Wait for PostgreSQL to be ready
until psql -U "$POSTGRES_USER" -c '\q' 2>/dev/null; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 1
done

echo "PostgreSQL is ready. Creating databases..."

# Create all application databases
create_db_and_user "${DB_NEXTCLOUD}" "${DB_USER_NEXTCLOUD}" "${DB_PASS_NEXTCLOUD}"
create_db_and_user "${DB_GITLAB}" "${DB_USER_GITLAB}" "${DB_PASS_GITLAB}"
create_db_and_user "${DB_OPENPROJECT}" "${DB_USER_OPENPROJECT}" "${DB_PASS_OPENPROJECT}"
create_db_and_user "${DB_BITWARDEN}" "${DB_USER_BITWARDEN}" "${DB_PASS_BITWARDEN}"
create_db_and_user "${DB_EZBOOKKEEPING}" "${DB_USER_EZBOOKKEEPING}" "${DB_PASS_EZBOOKKEEPING}"
create_db_and_user "${DB_CALIBRE}" "${DB_USER_CALIBRE}" "${DB_PASS_CALIBRE}"
create_db_and_user "${DB_REACTIVE_RESUME}" "${DB_USER_REACTIVE_RESUME}" "${DB_PASS_REACTIVE_RESUME}"
create_db_and_user "${DB_IMMICH}" "${DB_USER_IMMICH}" "${DB_PASS_IMMICH}"

echo "✓ All databases initialized successfully!"
