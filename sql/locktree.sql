WITH RECURSIVE l AS (
  SELECT pid, locktype, mode, granted, ROW(locktype,database,relation,page,tuple,virtualxid,transactionid,classid,objid,objsubid) obj FROM pg_locks
), pairs AS (
  SELECT w.pid waiter, l.pid locker, l.obj, l.mode
    FROM l w JOIN l ON l.obj IS NOT DISTINCT FROM w.obj AND l.locktype=w.locktype AND NOT l.pid=w.pid AND l.granted
   WHERE NOT w.granted
), tree AS (
  SELECT l.locker pid, l.locker root, NULL::record obj, NULL AS mode, 0 lvl, locker::text path, array_agg(l.locker) OVER () all_pids
    FROM ( SELECT DISTINCT locker FROM pairs l WHERE NOT EXISTS (SELECT 1 FROM pairs WHERE waiter=l.locker) ) l
  UNION ALL
  SELECT w.waiter pid, tree.root, w.obj, w.mode, tree.lvl+1, tree.path||'.'||w.waiter, all_pids || array_agg(w.waiter) OVER ()
    FROM tree JOIN pairs w ON tree.pid=w.locker AND NOT w.waiter = ANY ( all_pids )
)
SELECT (clock_timestamp() - a.xact_start)::interval(3) AS ts_age,
       replace(a.state, 'idle in transaction', 'idletx') state,
       (clock_timestamp() - state_change)::interval(3) AS change_age,
       a.datname,tree.pid,a.usename,a.client_addr,lvl,
       (SELECT count(*) FROM tree p WHERE p.path ~ ('^'||tree.path) AND NOT p.path=tree.path) blocked,
       repeat(' .', lvl)||' '||left(regexp_replace(query, E'\\s+', ' ', 'g'),100) query
  FROM tree
  JOIN pg_stat_activity a USING (pid)
 ORDER BY path;
