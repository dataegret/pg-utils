with totals as (
	select sum(total_time) AS total_time, greatest(sum(blk_read_time+blk_write_time), 1) as io_time,
	sum(total_time-blk_read_time-blk_write_time) as cpu_time, sum(calls) AS ncalls,
	sum(rows) as total_rows FROM pg_stat_statements
	WHERE TRUE
),
_pg_stat_statements as (
	select
    (select datname from pg_database where oid = p.dbid) as database,
    (select rolname from pg_roles where oid = p.userid) as username,
    regexp_replace(regexp_replace(query, E'\\?(::[a-zA-Z_]+)?(, *\\?(::[a-zA-Z_]+)?)+', '?', 'g'), E'\\$[0-9]+(::[a-zA-Z_]+)?(, *\\$[0-9]+(::[a-zA-Z_]+)?)*', '$N', 'g') as query, sum(total_time) as total_time, sum(blk_read_time) as blk_read_time,
    sum(blk_write_time) as blk_write_time, sum(calls) as calls, sum(rows) as rows
	from pg_stat_statements p
	where TRUE
	group by dbid, userid, query
),
totals_readable as (
	select to_char(interval '1 millisecond' * total_time, 'HH24:MI:SS') as total_time,
	(100*io_time/total_time)::numeric(20,2) AS io_time_percent,
	to_char(ncalls, 'FM999G999G990') AS total_queries,
	(select to_char(count(distinct query), 'FM999G999G990') from _pg_stat_statements) as unique_queries
	from totals
),
statements as (
	select
	(100*total_time/(select total_time from totals)) AS time_percent,
	(100*(blk_read_time+blk_write_time)/(select io_time from totals)) AS io_time_percent,
	(100*(total_time-blk_read_time-blk_write_time)/(select cpu_time from totals)) AS cpu_time_percent,
	to_char(interval '1 millisecond' * total_time, 'HH24:MI:SS') AS total_time,
	(total_time::numeric/calls)::numeric(20,2) AS avg_time,
	((total_time-blk_read_time-blk_write_time)::numeric/calls)::numeric(20, 2) AS avg_cpu_time,
	((blk_read_time+blk_write_time)::numeric/calls)::numeric(20, 2) AS avg_io_time,
	to_char(calls, 'FM999G999G990') AS calls,
	(100*calls/(select ncalls from totals))::numeric(20, 2) AS calls_percent,
	to_char(rows, 'FM999G999G999G990') AS rows,
	(100*rows/(select total_rows from totals))::numeric(20, 2) AS row_percent,
	database,
	username,
	query
	from _pg_stat_statements
	where ((total_time-blk_read_time-blk_write_time)/(select cpu_time from totals)>=0.01 or (blk_read_time-blk_write_time)/(select io_time from totals)>=0.01)
union all
	select
	(100*sum(total_time)::numeric/(select total_time from totals)) AS time_percent,
	(100*sum(blk_read_time+blk_write_time)::numeric/(select io_time from totals)) AS io_time_percent,
	(100*sum(total_time-blk_read_time-blk_write_time)::numeric/(select cpu_time from totals)) AS cpu_time_percent,
	to_char(interval '1 millisecond' * sum(total_time), 'HH24:MI:SS') AS total_time,
	(sum(total_time)::numeric/sum(calls))::numeric(20,2) AS avg_time,
	(sum(total_time-blk_read_time-blk_write_time)::numeric/sum(calls))::numeric(20, 2) AS avg_cpu_time,
	(sum(blk_read_time+blk_write_time)::numeric/sum(calls))::numeric(20, 2) AS avg_io_time,
	to_char(sum(calls), 'FM999G999G990') AS calls,
	(100*sum(calls)/(select ncalls from totals))::numeric(20, 2) AS calls_percent,
	to_char(sum(rows), 'FM999G999G999G990') AS rows,
	(100*sum(rows)/(select total_rows from totals))::numeric(20, 2) AS row_percent,
	'all' as database,
	'all' as username,
	'other' as query
	from _pg_stat_statements
	where not ((total_time-blk_read_time-blk_write_time)/(select cpu_time from totals)>=0.01 or (blk_read_time-blk_write_time)/(select io_time from totals)>=0.01)
),

statements_readable as (
	select row_number() over (order by s.time_percent desc) as pos,
	to_char(time_percent, 'FM90D0') || '%' AS time_percent,
	to_char(io_time_percent, 'FM90D0') || '%' AS io_time_percent,
	to_char(cpu_time_percent, 'FM90D0') || '%' AS cpu_time_percent,
	to_char(avg_io_time*100/avg_time, 'FM90D0') || '%' AS avg_io_time_percent,
	total_time, avg_time, avg_cpu_time, avg_io_time, calls, calls_percent, rows, row_percent,
	database, username, query
	from statements s
)

select E'total time:\t' || total_time || ' (IO: ' || io_time_percent || E'%)\n' ||
E'total queries:\t' || total_queries || E'\n' ||
E'unique queries:\t' || unique_queries || E'\n\n'
from totals_readable
union all
(select E'=============================================================================================================\n' ||
'pos:' || pos || E'\t total time: ' || total_time || ' (' || time_percent || ', CPU: ' || cpu_time_percent || ', IO: ' || io_time_percent || E')\t calls: ' || calls ||
' (' || calls_percent || E'%)\t avg_time: ' || avg_time || 'ms (IO: ' || avg_io_time_percent || E')\n' ||
'user: ' || username || E'\t db: ' || database || E'\t rows: ' || rows || E'\t query:\n' || query || E'\n'

from statements_readable order by pos);
