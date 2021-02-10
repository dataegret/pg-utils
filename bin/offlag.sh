#!/bin/bash

[ $# -lt 1 ] && { echo "Usage: ${0##*/} { master_host | segment_name | LSN }"; exit 1; }
MASTER=$1
set -o errexit pipefail

export PGCONNECT_TIMEOUT=10
case $MASTER in
  */*) M=$MASTER ;;
  00000???00*) M="${MASTER:8:8}/${MASTER:16:8}" ;;
  *) M=$( psql -h $MASTER -qAtXc "SELECT string_agg(CASE WHEN o=2 THEN lpad(p,8,'0') ELSE p END, '/') FROM unnest(string_to_array(pg_current_wal_lsn()::text, '/')) WITH ORDINALITY p(p,o);" ) ;;
esac
S=$( ps fx|awk '/(recovering|waiting for) [0-9A-F]*/{gsub(/ waiting$/, "", $0); print substr($NF, 9, 8) "/" substr($NF, 23, 2) "000000";}' )
TS=$( psql -qAtXc "SELECT format( '/ %s (%s / %ss)', pg_last_xact_replay_timestamp()::timestamp(0)
                                , (now()-pg_last_xact_replay_timestamp())::interval(0)
                                , extract(epoch FROM (now()-pg_last_xact_replay_timestamp())::interval(0)));" 2> /dev/null ) || true

MB=$(( 0xFF000000 * 0x${M%%/*} + 0x${M##*/} ))
SB=$(( 0xFF000000 * 0x${S%%/*} + 0x${S##*/} ))

D=$(( $MB - $SB ))
echo -e "$(date +%T) $M - $S = $( echo "print(\"%.2f\" % round($D/1024/1024.0,2))" | python3 )MB $TS"
