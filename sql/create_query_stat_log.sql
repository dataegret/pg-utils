
create extension IF NOT EXISTS pg_stat_statements;
create sequence query_stat_seq;
create table query_stat_log as select 1 as seq_num,now() as ts,* from query_stat_time;
create index query_stat_log_seq_num_key on query_stat_log(seq_num);
create index query_stat_log_ts_key on query_stat_log(ts);

