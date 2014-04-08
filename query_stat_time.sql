
with s AS
(SELECT sum(total_time) AS t,sum(blk_read_time+blk_write_time) as iot, sum(total_time-blk_read_time-blk_write_time) as cput, sum(calls) AS s,sum(rows) as r FROM pg_stat_statements WHERE dbid=(SELECT oid from pg_database where datname=current_database()))
,
_pg_stat_statements as (
select query,sum(total_time) as total_time, sum(blk_read_time) as blk_read_time, sum(blk_write_time) as blk_write_time, sum(calls) as calls, sum(rows) as rows
from pg_stat_statements
where dbid=(SELECT oid from pg_database where datname=current_database())
group by query
)

SELECT
(100*total_time/(SELECT t FROM s))::numeric(20,2) AS time_percent,
(100*(blk_read_time+blk_write_time)/(SELECT iot FROM s))::numeric(20,2) AS iotime_percent,
(100*(total_time-blk_read_time-blk_write_time)/(SELECT cput FROM s))::numeric(20,2) AS cputime_percent,
total_time::numeric(20,2) as total_time,
(total_time*1000/calls)::numeric(20,2) AS avg_time,
((blk_read_time+blk_write_time)*1000/calls)::numeric(20,2) AS avg_io_time,
calls,
(100*calls/(SELECT s FROM s))::numeric(20,2) AS calls_percent,
rows,
(100*rows/(SELECT r from s))::numeric(20,2) AS row_percent,
query
FROM _pg_stat_statements
WHERE
(total_time)/(SELECT t FROM s)>=0.02

UNION all

SELECT
(100*sum(total_time)/(SELECT t FROM s))::numeric(20,2) AS time_percent,
(100*sum(blk_read_time+blk_write_time)/(SELECT iot FROM s))::numeric(20,2) AS iotime_percent,
(100*sum(total_time-blk_read_time-blk_write_time)/(SELECT cput FROM s))::numeric(20,2) AS cputime_percent,
sum(total_time)::numeric(20,2),
(sum(total_time)*1000/sum(calls))::numeric(10,3) AS avg_time,
(sum(blk_read_time+blk_write_time)*1000/sum(calls))::numeric(10,3) AS avg_io_time,
sum(calls),
(100*sum(calls)/(SELECT s FROM s))::numeric(20,2) AS calls_percent,
sum(rows),
(100*sum(rows)/(SELECT r from s))::numeric(20,2) AS row_percent,
'other' AS query
FROM _pg_stat_statements
WHERE
(total_time)/(SELECT t FROM s)<0.02

ORDER BY 1 DESC;

