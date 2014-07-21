
with s AS
(SELECT sum(total_time) AS t,sum(calls) AS s,sum(rows) as r FROM pg_stat_statements WHERE dbid=(SELECT oid from pg_database where datname=current_database()))
SELECT
(100*total_time/(SELECT t FROM s))::numeric(20,2) AS time_percent,
total_time::numeric(20,2) as total_time,
(total_time*1000/calls)::numeric(10,3) AS avg_time,
calls,
(100*calls/(SELECT s FROM s))::numeric(20,2) AS calls_percent,
rows,
(100*rows/(SELECT r from s))::numeric(20,2) AS row_percent,
query
FROM pg_stat_statements
WHERE
calls/(SELECT s FROM s)>=0.01
AND dbid=(SELECT oid from pg_database where datname=current_database())

UNION all

SELECT
(100*sum(total_time)/(SELECT t FROM s))::numeric(20,2) AS time_percent,
sum(total_time)::numeric(20,2),
(sum(total_time)*1000/sum(calls))::numeric(10,3) AS avg_time,
sum(calls),
(100*sum(calls)/(SELECT s FROM s))::numeric(20,2) AS calls_percent,
sum(rows),
(100*sum(rows)/(SELECT r from s))::numeric(20,2) AS row_percent,
'other' AS query
FROM pg_stat_statements
WHERE
calls/(SELECT s FROM s)<0.01
AND dbid=(SELECT oid from pg_database where datname=current_database())

ORDER BY 4 DESC;

