#!/bin/bash

# Script based on https://github.com/mrts/docker-postgresql-multiple-databases

set -e
set -u

function create_user_and_database() {
 local database=$1
 local password=$2
 echo "Creating user and database '$database'"
 psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
     CREATE USER $database WITH ENCRYPTED PASSWORD '$password';
     CREATE DATABASE $database;
     GRANT ALL PRIVILEGES ON DATABASE $database TO $database;
EOSQL
}

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
 echo "Multiple database creation requested"
 for user_pass in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
   create_user_and_database $(echo $user_pass | tr ':' ' ')
 done
 echo "Multiple databases created"
fi
