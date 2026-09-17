#!/bin/bash

# Variable
CUSTOMER="demo"

# set encoding
# ENCODING="ENCODING 'UTF8' LC_COLLATE 'en_US.utf8' LC_CTYPE 'en_US.utf8'"

# Function to generate password and its base64 sha256 hash
generate_password_with_hash() {
  PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+' | head -c 20)
  HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}' | xxd -r -p | base64 -w 0)
  echo "$PASSWORD $HASH"
}

# Generate passwords and hashes
read KEYCLOAK_PASSWORD KEYCLOAK_HASH <<< $(generate_password_with_hash)
read ADR_PASSWORD_BACK ADR_HASH <<< $(generate_password_with_hash)

# Create users first
psql -U postgres -h dbhost -c "CREATE USER keycloak_${CUSTOMER} WITH PASSWORD '${KEYCLOAK_PASSWORD}';"
psql -U postgres -h dbhost -c "CREATE USER ADR_${CUSTOMER}_BACK WITH PASSWORD '${ADR_PASSWORD_BACK}';"

psql -U postgres -h dbhost -c "CREATE ROLE keycloak_${CUSTOMER} NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"
psql -U postgres -h dbhost -c "CREATE ROLE ADR_${CUSTOMER}_BACK NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"  

# Create databases and assign ownership
psql -U postgres -h dbhost -c "CREATE DATABASE app_keycloak_${CUSTOMER} ;"
psql -U postgres -h dbhost -c "CREATE DATABASE app_adr_${CUSTOMER}_BACK ;"

# Grant all privileges on databases to their respective owners
psql -U postgres -h dbhost -c "GRANT ALL PRIVILEGES ON DATABASE app_keycloak_${CUSTOMER} TO keycloak_${CUSTOMER};"
psql -U postgres -h dbhost -c "GRANT ALL PRIVILEGES ON DATABASE app_adr_${CUSTOMER}_BACK TO ADR_${CUSTOMER}_BACK;"

# Output passwords and hashes
echo "keycloak_${CUSTOMER} password: ${KEYCLOAK_PASSWORD}"
echo "Keycloak hash: ${KEYCLOAK_HASH}"
echo "ADR_${CUSTOMER}_BACK password: ${ADR_PASSWORD_BACK}"


# pg_hba.conf recommendations (add manually)
echo ""
echo "Add to pg_hba.conf (restrictive):"
echo "# TYPE  DATABASE        USER            ADDRESS                 METHOD"
echo "local   all             postgres -h dbhost                                peer"
echo "local   all             all                                     peer"
echo "host    app_keycloak_${CUSTOMER}  keycloak_${CUSTOMER}  127.0.0.1/32            md5"
echo "host    app_adr_${CUSTOMER}_FRONT      ADR_${CUSTOMER}_FRONT      127.0.0.1/32            md5"
echo "host    app_adr_${CUSTOMER}_BACK      ADR_${CUSTOMER}_BACK      127.0.0.1/32            md5"

# Import DB
echo "Importing ADR Schema ---- TODO"
echo "update password hash of ADR USER on the before last line of subsequent file and run the next command"
echo "psql -U postgres -h dbhost -d app_adr_${CUSTOMER}_BACK -f "C:\\AMPACIMON\\adr\\apcm-payara-bundle\\scripts\\sql\\latest\\postgresql\\1-create-database-20260429.sql""

