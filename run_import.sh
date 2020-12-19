#!/bin/bash

set -x

function createPostgresConfig() {
  cp /etc/postgresql/12/main/postgresql.custom.conf.tmpl /etc/postgresql/12/main/conf.d/postgresql.custom.conf
  sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/12/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/12/main/conf.d/postgresql.custom.conf
}

function setPostgresPassword() {
    sudo -u postgres psql -c "ALTER USER renderer PASSWORD '${PGPASSWORD:-renderer}'"
}

# Ensure that database directory is in right state
chown postgres:postgres -R /var/lib/postgresql
if [ ! -f /var/lib/postgresql/12/main/PG_VERSION ]; then
    sudo -u postgres /usr/lib/postgresql/12/bin/pg_ctl -D /var/lib/postgresql/12/main/ initdb -o "--locale C.UTF-8"
fi

# Initialize PostgreSQL
createPostgresConfig
service postgresql start
sudo -u postgres createuser renderer
sudo -u postgres createdb -E UTF8 -O renderer gis
sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"
setPostgresPassword

# Import data
sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore --tag-transform-script /home/renderer/src/openstreetmap-carto/openstreetmap-carto.lua -C 4096 --number-processes 8 -S /home/renderer/src/openstreetmap-carto/openstreetmap-carto.style /home/asia-latest.osm.pbf

# Create indexes
sudo -u postgres psql -d gis -f indexes.sql

# Register that data has changed for mod_tile caching purposes
touch /var/lib/mod_tile/planet-import-complete

service postgresql stop

exit 0
