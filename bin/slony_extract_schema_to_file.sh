#!/bin/sh
# ----------
# slony1_extract_schema.sh
#
#       Script to extract the user schema of a slony node in the original
#       state with all Slony related cruft removed.
# ----------

# ----
# Check for correct usage
# ----
if test $# -ne 5 ; then
        echo "usage: $0 dbname clustername tempdbhost tempdbname filename" >&2
        exit 1
fi

# ----
# Remember call arguments and get the nodeId of the DB specified
# ----
dbname=$1
cluster=$2
tmphost=$3
tmpdb=$4
file=$5

nodeid=`psql -q -At -c "select \"_$cluster\".getLocalNodeId('_$cluster')" $dbname`

TMP=tmp.$$

# ----
# Print a warning for sets originating remotely that their
# triggers and constraints will not be included in the dump.
# ----
psql -q -At -c "select 'Warning: Set ' || set_id || ' does not origin on node $nodeid - original triggers and constraints will not be included in the dump' from \"_$cluster\".sl_set where set_origin <> $nodeid" $dbname >&2

#prepare temp db
psql -h $tmphost -q -c "DROP DATABASE IF EXISTS $tmpdb"
createdb -h $tmphost $tmpdb

#schema stuff
pg_dump -i --no-tablespaces -s $dbname >~/tmp/$TMP.sql
psql -q -1 -h $tmphost $tmpdb -f ~/tmp/$TMP.sql
rm ~/tmp/$TMP.sql

#slony stuff
pg_dump -i -a -n _$cluster $dbname >~/tmp/${TMP}_slony.sql

psql -q -t -c "select 'update \"_$cluster\".sl_table set tab_reloid=(select C.oid from \"pg_catalog\".pg_class C, \"pg_catalog\".pg_namespace N where C.relnamespace = N.oid and C.relname = ''' || C2.relname || ''' and N.nspname = ''' || N2.nspname || ''') where tab_id = ''' || tab_id || ''';' from \"_$cluster\".sl_table T, \"pg_catalog\".pg_class C2, \"pg_catalog\".pg_namespace N2 where T.tab_reloid = C2.oid and C2.relnamespace = N2.oid" $dbname >>~/tmp/${TMP}_slony.sql

psql -q -t -c "select 'update \"_$cluster\".sl_sequence set seq_reloid=(select C.oid from \"pg_catalog\".pg_class C, \"pg_catalog\".pg_namespace N where C.relnamespace = N.oid and C.relname = ''' || C2.relname || ''' and N.nspname = ''' || N2.nspname || ''') where seq_id = ''' || seq_id || ''';' from \"_$cluster\".sl_sequence T, \"pg_catalog\".pg_class C2, \"pg_catalog\".pg_namespace N2 where T.seq_reloid = C2.oid and C2.relnamespace = N2.oid" $dbname >>~/tmp/${TMP}_slony.sql

psql -q -1 -h $tmphost $tmpdb -f ~/tmp/${TMP}_slony.sql > /dev/null
rm ~/tmp/${TMP}_slony.sql

# ----
# Step 3.
#
# Use the slonik "uninstall node" command to restore the original schema.
# ----
slonik 2>/dev/null <<_EOF_
cluster name = $cluster;
node $nodeid admin conninfo = 'dbname=$tmpdb host=$tmphost';
uninstall node (id = $nodeid);
_EOF_

# ----
# Step 4.
#
# Use pg_dump on the temporary database to dump the user schema
# to stdout.
# ----
pg_dump -h $tmphost -N tables_to_drop -i -s -f $file $tmpdb

# ----
# Remove temporary files and the database
# ----
psql -h $tmphost -q -c "DROP DATABASE IF EXISTS $tmpdb" >/dev/null 2>&1

