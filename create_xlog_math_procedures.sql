
-- For documentation on these functions, please see blog post at:
-- http://www.databasesoup.com/2012/10/determining-furthest-ahead-replica.html

-- determines current xlog location as a monotonically increasing numeric.
CREATE OR REPLACE FUNCTION xlog_location_numeric()
RETURNS numeric
LANGUAGE plpgsql
as $f$
DECLARE cloc text;
        floc text[];
        numloc numeric;
BEGIN

-- find out if we're on a replica or not
IF pg_is_in_recovery() THEN
        -- on replicas, this is the receive location
        cloc := pg_last_xlog_receive_location();
ELSE
        -- on standalone, it's the xlog location
        cloc := pg_current_xlog_location();
END IF;

-- extract the two portions of the log location
floc := regexp_matches(cloc, $x$^([\w\d]+)/([\w\d]+)$$x$);

-- convert these to numerics and multiply the file position
-- by ff000000, then add.
EXECUTE $q$SELECT ( x'$q$ || floc[1] || $q$'::int8::numeric )
        * ( x'ff000000'::int8::numeric )
        + x'$q$ || floc[2] || $q$'::int8::numeric $q$
INTO numloc;

RETURN numloc;

END;$f$;

-- gives approximate current replay lag on a replica 
-- in megabytes

CREATE OR REPLACE FUNCTION replay_lag_mb()
RETURNS numeric
LANGUAGE plpgsql
as $f$
DECLARE cloc text;
        floc text[];
        recv_numloc numeric;
        rep_numloc numeric;
        mb_lag numeric;
        servver numeric;
BEGIN

-- get version number
SELECT setting
INTO servver 
FROM pg_settings WHERE name = 'server_version_num';

-- if this is 9.2 or later, we can shortcut the calculations
-- and use location_diff
IF servver >= 90200 THEN
  mb_lag = round( pg_xlog_location_diff(pg_last_xlog_receive_location(), pg_last_xlog_replay_location()) /
        (1024^2)::numeric, 1 );
  RETURN mb_lag;
END IF;

-- extract the two portions of the received log location
floc := regexp_matches(pg_last_xlog_receive_location(), $x$^([\w\d]+)/([\w\d]+)$$x$);

-- convert these to numerics and multiply the file position
-- by ff000000, then add.
EXECUTE $q$SELECT ( x'$q$ || floc[1] || $q$'::int8::numeric )
        * ( x'ff000000'::int8::numeric )
        + x'$q$ || floc[2] || $q$'::int8::numeric $q$
INTO recv_numloc;

-- extract data from replay location
floc := regexp_matches(pg_last_xlog_replay_location(), $x$^([\w\d]+)/([\w\d]+)$$x$);

-- convert these to numerics and multiply the file position
-- by ff000000, then add.
EXECUTE $q$SELECT ( x'$q$ || floc[1] || $q$'::int8::numeric )
        * ( x'ff000000'::int8::numeric )
        + x'$q$ || floc[2] || $q$'::int8::numeric $q$
INTO rep_numloc;

-- compute difference

mb_lag = round ( ( recv_numloc - rep_numloc ) / ( 1024^2 )::numeric, 1 );

RETURN mb_lag;

END;$f$;


-- returns true if replay is caught up on the replica.

CREATE OR REPLACE FUNCTION all_replayed()
RETURNS BOOLEAN
LANGUAGE sql
AS $f$
SELECT pg_last_xlog_receive_location() =
pg_last_xlog_replay_location();
$f$;


