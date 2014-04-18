## SQL snippets (or more beautiful description)

### 83compat.sql

### check_are_all_subscribed.sql

### check_missing_grants.sql

### check_strange_fk.sql

### check_uniq_indexes.sql
Searhes the tables which do not have UNIQUE CONSTRAINTs.

### create_db_activity_view9.2.sql and create_db_activity_view.sql
Creating VIEWs for viewing running postgres processes with transactions in which the runtime is more than 100ms, and queries with runtime more than 500ms. Requires enabled track_activities in postgresql.conf for proper display the state of processes. This views allows to view only running processes, cutting idle processes. create_db_activity_view.sql is used in PostgreSQL version 9.1 and older, create_db_activity_view9.2.sql used since PostgreSQL 9.2.

Columns:

* ts_age - transaction runtime

* state - process state (active, idle, idle in transaction, idle in transaction (aborted), fastpath function call or disabled when track_activities off)

* query_age - current query runtime;

* change_age - time elapsed since the last change of process state;

* datname - database name in which process is connected;

* pid - postgres process id;

* usename - database username which used in postgres process for running query;

* waiting - set in true if current process waiting other query (sometimes not good);

* client_addr - remote client ip address which connected to postgres;

* client_port - remote client port number which is used in connection;

* query - query text which is currently executed in process;

### create_query_stat_cpu_time_view.sql
Creating query_stat_cpu_time VIEW for viewing queries with runtime more or equal 0.02 seconds (IO time not accounting). Require enabled pg_stat_statements and optionally track_io_timings enabled in postgresql.conf. Columns description see below in create_query_stat_time_view.sql.

### create_query_stat_io_time_view.sql
Creating query_stat_io_time VIEW for viewing queries with IO time more or equal 0.02 seconds. Also require pg_stat_statements and track_io_timings in postgresql.conf. Columns description see below in create_query_stat_time_view.sql.

### create_query_stat_log.sql

### create_query_stat_time_view.sql
Creating query_stat_time VIEW for viewing queries with total runtime more or equal 0.02 seconds (time spent on block IO also included). Require enabled pg_stat_statements and track_io_timings in postgresql.conf.

Columns:

* time_percent - total query runtime measured in %, relative to the runtime of all queries;

* iotime_percent - query time spent on block IO in %, relative to the runtime of all queries;

* cputime_percent - query runtime  (without time spent on block IO) in %, relative to the runtime of all queries;

* total_time - total runtime of this query;

* avg_time - average runtime for this query;

* avg_io_time - average time spent on IO for this query;

* calls - numbers of calls for this query;

* calls_percent - numbers of calls for this query in %, relative to the all queries calls;

* rows - number of rows was returned by this query;

* row_percent - row was returned by this query in %, relative to the all rows returned by all others queries;

* query - query text

Note: all queries which runtime less 0.02 seconds, accounts into dedicated 'other' query.

### create_slonik_set_full.sql

### create slonik_set_incremental.sql

### create_xlog_math_procedures.sql
This snippets create following funtions:

* xlog_location_numeric - shows current WAL position in decimal expression.

* replay_lag_mb - shows estimated lag between master and standby server in megabytes.

* all_replayed - returns true if all WAL are replayed (zero lag).

Usage: ???

### db_activity.sql and db_activity9.2.sql

### dirty_to_read_stat.sql
Some statistics for "dirty" buffers. Require pg_buffercache extensions.

Columns: relation - object name and schema which object belongs;

* relkind - object type (r = ordinary table, i = index, S = sequence, v = view, c = composite type, t = TOAST table);

* tblsp - tablespace in which object is stored;

* relsize - object size, in megabytes;

* %_cached - estimated amount of pages in %, which is cached;

* disk_read - read directly from disk (difference between values from pg_stat_get_blocks_fetched and pg_stat_get_blocks_hit);

* dirty_size - dirty pages size, in megabytes;

* buffer_data.%_dirty - dirty pages, in %;

* read_to_dirty_ratio - ratio of the amount of data read from the disk to the amount of dirty pages, i.e. average amount of reading per dirty.

Udage: ???

### generate_drop_items.sql

### index_candidates_from_ssd.sql and index_candidates_to_ssd.sql
Display indexes which should be moved from/to SSD.

Columns:

* table - table which index belongs;

* index - index name;

* tblsp - tablespace where index is stored;

* size - pretty table size

* disk - amount of disk block reads from index;

* disk_rat - amount of disk reads, in %;

* d_w_rat - the ratio of the number of block read from the disk to the total change in rows in a table (insert + update + delete - hot_update);

* write - total writes (in tuples) in the table (insert + update + delete - hot_update);

* idx_scan - number of index scan;

* idx_tup_read - number of rows read through the index;

Low d_w_rat value shows low disk reads with relatively high amount of changes inside relation (this behaviour influnces to the index permanent rebuilding, more changes in table, more changes in index). For displaing indexes which recommended move from SSD, a following conditions are used: display indexes with d_w_rat < 25 and tblsp = "ssd".
High d_w_rat value shows high disk reads (bad) with relatively low amount of changes in the table. For displaing indexes which are recommended move on SSD, used following conditions: d_w_rat > 10, disk > 1000 and tblsp != "ssd".

### index_disk_activity.sql
Display indexes disk reads statistics.

Columns:

* table - tablename which index is belongs;

* index - index name;

* tblsp - tablespace where index is stored;

* size - pretty index size;

* disk - total amount of disk blocks reads with index;

* disk_rat - amount of disk reads in %;

* d_w_rat - the ratio of the number of block read from the disk to the total change in rows in a tableо (insert + update + delete - hot_update);

* write - total writes (in tuples) in the table (insert + update + delete - hot_update);

* idx_scan - number of index scan;

* buffer_data.dirty - pretty size of dirty data;

* buffer_data.%_dirty - ammount of dirty data, in %.

Displaing only those indexes which total amount of disk blocks reads (disk column) more than 100 blocks.

### indexes_with_null.sql
Show indexes with NULL data.

Columns:

* table - table name which index belongs;

* index - index name;

* field - column name;

* statnullfrac - ratio of NULL in column;

* indexsize - index size;

* indexdef - index definition.

Shows only indexes with statnullfrac > 0.5 and_size > 81920 bytes.

### low_used_indexes.sql
Show indexes which low or not used.

Columns:

* schemaname.relname - schema and table which index belongs;

* indexrelname - index name;

* idx_scan - number of index scans;

* write_activity - total amount of writes into table which index belongs (INSERT/UPDATE/DELETE);

* seq_scan - number of sequential scans for this table;

* n_live_tup - number of live rows in the table;

* size - index size.

Show indexes with following conditions: (idx_scan / write_activity) < 0.01 и write_activity > 10000.

### master_wal_position.sql

### query_stat_counts.sql
Display query useful statistics: queries, number of calls, runtime, averages.

Columns:

* time_percent - this query runtime relatively all queries runtime, in %;

* total_time - total amount of time which this query runs;

* avg_time - average query runtime in seconds;

* calls - number of query calls;

* calls_percent - this query number of calls relatively to all queries, in %;

* rows - number of rows returned by this query;

* row_percent - number of rows returned by this query relatively to all rows returned by all other queries, in %;

* query - query text.

All queries with following condition: (calls / sum(calls)) >= 0.01, are displaing in dedicated query whic named 'other'.

### query_stat_cpu_time.sql, query_stat_io_time.sql, query_stat_rows.sql, query_stat_time.sql 
Queries similar to query_stat_cpu_time, query_stat_io_time, query_stat_time VIEWS and displaing queries runtime with cpu and block IO accounting. Require pg_stat_statement and track_io_timings enabled in postgresql.conf.

### redundant_indexes.sql
Show redundant indexes - indexes which are built with common column which is present in both indexes.

Columns:

* main_index - index defintion which is estmated as main;

* redundant_index - index definition which is estimated as redundant;

* redundant_index_size - pretty size of redundant index.

### seq_scan_tables.sql
Show tables with high amount of sequential scans.

Columns:

* schemaname.relname - table name;

* n_live_tup - number of live rows in the table;

* seq_scan - number of sequential scan on that table;

* seq_tup_read - number of rows which returned by sequential sqans;

* write_activity - total amount of writes in the table (INSERT/UPDATE/DELETE);

* index_count - number of indexes which are belongs to the table;

* idx_scan - number of index scans for all table indexes;

* idx_tup_fetch - number of rows which was fetched by index scans.

Only following tables are shown: with seq_scan > 0 and seq_tup_read > 100000

### set_default_grants.sql
Setup DEFAUlT PRIVILEGES for all new object created by postgres for role_ro and role_rw roles.

role_ro: select on sequences; select on tables.

role_rw: select,usage on sequences; select,insert,update,delete on tables.

### set_missing_grants.sql
Setup appropriate GRANTs for role_ro (SELECT) and role_rw (SELECT,INSERT,UPDATE,DELETE,USAGE) on tables, views and sequences in case when acl of these objecta are null or not appropriate by this snippet.

### slave_wal_position.sql
Shows current WAL state: position received from master and replayed at this moment.

### slony_tables.sql
Show tables list from _slony.sl_table

### sync_tablespaces.sql
Find indexes which stored in different tablespace then their tables and move on indexes (ALTER INDEX indexname SET TABLESPACE tablespace) into tablespace where  the parent table is stored.

### table_candidates_from_ssd.sql and table_candidates_to_ssd.sql
Show tables which should be moved from SSD (high writes, low reads) or to SSD (low writes, high reads).

Columns:

* nspname.relname - table name;

* tblsp - tablespace where table is stored;

* size - pretty table size, include TOAST;

* ratio - amount of writes (insert/delete/2*update) relatively to all disk reads (pg_stat_get_blocks_fetched - pg_stat_get_blocks_hit), TOAST included;

* disk - amount of disk writes (pg_stat_get_blocks_fetched - pg_stat_get_blocks_hit), TOAST included;

* disk% - amount of disk reads for this table relatively to all disk reads (with TOAST), in %;

* rt_d_rat - ratio of rows returned from table and this table indexes relatively to disk reads for this table;

* r_tuples - number of rows returned from the table and her indexes;

* write - amount of writes in rows (insert/delete/2*update) include TOAST;

* write% - ratio of disk writes related to this table relatively to total amount of writes on all tables (with TOAST);

* n_tup_ins - number of inserted rows, include TOAST;

* n_tup_upd - number of updated rows, include TOAST;

* n_tup_del - number of deleted rows, include TOAST.

Tables which should be moved from SSD: tblsp="ssd" and ratio < 20 (high amount pf writes and low reads)

Tables which should be moved to SSD: tblsp != "ssd" and ratio > 10 (low amount of writes, and high reads)

### table_disk_activity.sql
Show disk activity for tables.

Columns:

* nspname.relname - table name;

* tblsp - tablespace where table is stored;

* size - pretty table size, include TOAST;

* ratio - ratio of writes (insert/delete/2*update) relatively to disk reads (pg_stat_get_blocks_fetched - pg_stat_get_blocks_hit), include TOAST;

* disk% - ratio of disk reads related to this table relatively to total disk reads from all tables (include TOAST);

* rt_d_rat - ratio of returned rows from this table and indexes relatively to disk reads for this table;

* r_tuples - number of rows returned from this tables and indexes;

* write - amount ow writes in rows (insert/delete/2*update), include TOAST;

* write% - amount of writes for this table relatively to the total amount of writes for all tables, include TOAST;

* dirty - pretty size of dirty pages for this tables;

* %_dirty - amount of dirty pages relatively to the total amount og pages.

Only that tables are displayed: with pg_stat_get_tuples_fetched > 100 and write > 10

### table_index_write_activity.sql and table_write_activity.sql
Shows amount of index writes (table_index_write_activity.sql) and table writes (table_write_activity.sql).

Columns:

* schemaname.relname - table name;

* size - pretty table size, without indexes;

* tblsp - tablespace where table is stored;

* seq_scan - number of sequential scans for this table;

* idx_scan - number of index scans for this table;

* n_tup_ins - number of inserted rows;

* n_tup_upd - number of updated rows;

* n_tup_del - number of deleted rows;

* total - total amount for writes (INSERT/UPDATE/DELETE) for table_index_write_activity.sql and amount INSERT/2*UPDATE/DELETE for table_write_activity.sql;

* hot_rate - amount of HOT among all update operations;

* fillfactor - fillfactor value for table.

Conditions for table_index_write_activity.sql: total > 100

Conditions for table_write_activity.sql: total > 0
