#!/bin/bash
# Description: Check various PostgreSQL settings and parameters

err() { echo $@; exit 1; }

PGPATH="/usr/pgsql-9.0/bin:/usr/pgsql-9.1/bin:/usr/pgsql-9.2/bin:/usr/pgsql-9.3/bin:/usr/pgsql-9.4/bin"
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:$PGPATH"

red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

PGCONNOPTS="-U postgres"

global_checks() {
echo "${yellow}Checking target: Global checks${reset}"
}

config_checks() {
echo "${yellow}Checking target: Configuration options${reset}"
echo "* fsync:" $(psql -qAtX $PGCONNOPTS -c "SELECT setting FROM pg_settings WHERE name = 'fsync'")
echo "* zero_damaged_pages:" $(psql -qAtX $PGCONNOPTS -c "SELECT setting FROM pg_settings WHERE name = 'zero_damaged_pages'")
echo "* debug_assertions:" $(psql -qAtX $PGCONNOPTS -c "SELECT setting FROM pg_settings WHERE name = 'debug_assertions'")
}

database_checks() {
echo "${yellow}Checking target: Custom checks${reset}"
    # check invalid indexes
    echo -n "* Invalid indexes: "
    for datname in $(psql -qAtX $PGCONNOPTS -c "SELECT datname FROM pg_database WHERE NOT datistemplate");
    do  
        cnt=$(psql -qAtX $PGCONNOPTS -d $datname -c "SELECT count(*) FROM pg_index WHERE NOT indisvalid")
        [[ $cnt -gt 0 ]] && dblist="$dblist $datname"
    done
        [[ -n $dblist ]] && echo -e "Found in${yellow}$dblist${reset}." || echo "Not found."
  
    # pg_catalog size
    dblist=""
    echo -n "* Huge pg_catalog (size over than 500MB): "
    for datname in $(psql -qAtX $PGCONNOPTS -c "SELECT datname FROM pg_database WHERE NOT datistemplate");
    do  
        size=$(psql -qAtX $PGCONNOPTS -d $datname -c "SELECT (sum(pg_total_relation_size(relname::regclass)) / 1024 / 1024)::int FROM pg_stat_sys_tables WHERE schemaname = 'pg_catalog'")
        [[ $size -gt 500 ]] && dblist="$dblist $datname"
    done
        [[ -n $dblist ]] && echo -e "${yellow}$dblist${reset}." || echo "OK."
}

main() {
    global_checks
    config_checks
    database_checks
}

main
