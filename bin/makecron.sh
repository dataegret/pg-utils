#!/bin/bash
# Description:  Script generates common list of crontabs.
# Author:       Lesovsky A.V.
# Usage:        makecron.sh email email ...

# Show usage if no emails
[[ $# -eq 0 ]] && { echo -e "Usage:\n  $0 email+customer@domain.tld email ..."; exit 1; }

# Passed list of email addresses.
EMAILSLIST=$@

# Take first email and extract customer's name.
IFS=' ' read -r -a EMAILS <<< $EMAILSLIST
[[ ${EMAILS[0]} != *"+"* ]] && { echo -e "ERROR: invaild first email\nHINT: use the following email format: email+customer@domain"; exit 1; }

# List of connected standby nodes.
STANDBYLIST=$(psql -qAtX -U postgres -c "select string_agg(host(client_addr), ' ') from pg_stat_replication")

# Customer name.
CUSTOMER_NAME=$(echo ${EMAILS[0]} |cut -d" " -f1 |cut -d@ -f1 |cut -d+ -f2)

# Entitled customer name, e.g. 'customer' becomes 'Customer'.
CUSTOMER_NAME_TITLE=$(echo $CUSTOMER_NAME |sed 's/[^ ]\+/\L\u&/g')

# An absolute path to Postgres log files, suppose logging_collector already enabled.
LOG_DIRECTORY=$(psql -qAtX -U postgres -c "select case when left(ld,1) = '/' then ld else dd||'/'||ld end as log_directory from current_setting('data_directory') dd, current_setting('log_directory') ld")

# Hours in current timezone shifted to Europe/Moscow timezone.
RESET_HOUR=$(date --date='TZ="Europe/Moscow" 23' +"%H")
REPORT_HOUR=$(date --date='TZ="Europe/Moscow" 00' +"%H")
DELETE_HOUR=$(date --date='TZ="Europe/Moscow" 04' +"%H")

# Sanity check
[[ -z $CUSTOMER_NAME ]] && { echo -e "ERROR: failed to obtain customer name"; exit 1; }
[[ -z $LOG_DIRECTORY ]] && { echo -e "ERROR: failed to obtain log_directory setting"; exit 1; }

envsubst <<EOF
MAILTO=support-cron+$CUSTOMER_NAME@dataegret.com
# all times given in Europe/Moscow timezone

# pg_stat_statements report
59 $REPORT_HOUR * * *	/usr/bin/psql -XAt -U postgres -f ~/stuff/sql/global_reports/query_stat_total.sql | /usr/bin/mail -e -s "Daily report of pg_stat_statements for `/bin/date "+\%Y-\%m-\%d"` from `hostname` database at $CUSTOMER_NAME_TITLE" $EMAILSLIST'

# pg_stat_statements reset
00 $RESET_HOUR * * *	/usr/bin/psql -t -c "select pg_stat_statements_reset()" > /dev/null

# Terminate long transactions
#* * * * *	/usr/bin/psql -Xxt1 -c "SELECT pg_terminate_backend(pid),now(),now()-xact_start as duration,* from pg_stat_activity where (now() - pg_stat_activity.xact_start) > '60 min'::interval and state<>'idle' and client_addr is not null and usename not in ('postgres', 'backuper', 'replica')" | grep -vE '^(|\(No rows\))$'

# Delete old log files
00 $DELETE_HOUR  * * *	find $LOG_DIRECTORY -name 'post*.log*' -type f -mtime +7 -delete

# Lower io priority
* * * * *       ps -u postgres x | grep -Ei 'autovacuum|COPY|pg_dump|clickcast_background|: logger process|: checkpointer process|: writer process|: autovacuum launcher process|: stats collector process|lzop|wal-e' | grep -vE 'grep|pgbouncer' | perl -pe 's/^\s*(\d+) .*$/\$1/' | xargs --no-run-if-empty -I $ ionice -c 3 -t -p $
# Lower cpu priority
* * * * *       ps -u postgres x | grep -Ei 'autovacuum|COPY|pg_dump|clickcast_background|: logger process|: checkpointer process|: writer process|: autovacuum launcher process|: stats collector process|lzop|wal-e' | grep -vE 'grep|pgbouncer' | perl -pe 's/^\s*(\d+) .*$/\$1/' | xargs --no-run-if-empty -I $ renice -n 20 -p $ >/dev/null 2>/dev/null
EOF

if [[ -n $STANDBYLIST ]]; then
echo -e "\n# MASTER DB ONLY\n# Check replication lag"
  for s in $STANDBYLIST;
    do
echo "#*/5 * * * *    ~/stuff/bin/check_replication_lag.pl localhost ${s} yes 536870912"
    done
fi
