CREATE EXTENSION IF NOT EXISTS dblink;
ALTER EXTENSION dblink UPDATE;

--current version of code
CREATE OR REPLACE FUNCTION index_watch.version()
RETURNS TEXT AS
$BODY$
BEGIN
    RETURN '0.6';
END;
$BODY$
LANGUAGE plpgsql IMMUTABLE;

--minimum table structure version required
CREATE OR REPLACE FUNCTION index_watch._check_structure_version()
RETURNS VOID AS
$BODY$
DECLARE
  _tables_version INTEGER;
  _required_version INTEGER :=1;
BEGIN
    SELECT version INTO STRICT _tables_version FROM index_watch.tables_version;	
    IF (_tables_version<_required_version) THEN
	RAISE EXCEPTION 'current tables version % is less than minimally required % for % code version, please update tables structure', _tables_version, _required_version, index_watch.version();
    END IF;
    RETURN;
END;
$BODY$
LANGUAGE plpgsql STABLE;

--convert patterns from psql format to like format
CREATE OR REPLACE FUNCTION index_watch._pattern_convert(_var text)
RETURNS TEXT AS
$BODY$
BEGIN
    --replace * with .*
    _var := replace(_var, '*', '.*');
    --replace ? with .
    _var := replace(_var, '?', '.');

    RETURN  '^('||_var||')$';
END;
$BODY$
LANGUAGE plpgsql STRICT IMMUTABLE;


CREATE OR REPLACE FUNCTION index_watch.get_setting(_datname text, _schemaname text, _relname text, _indexrelname text, _key TEXT)
RETURNS TEXT AS
$BODY$
DECLARE
    _value TEXT;
BEGIN	
    PERFORM index_watch._check_structure_version();
    --RAISE NOTICE 'DEBUG: |%|%|%|%|', _datname, _schemaname, _relname, _indexrelname;
    SELECT _t.value INTO _value FROM (
      --per index setting 	
      SELECT 1 AS priority, value FROM index_watch.config WHERE 
        _key=config.key 
	AND (_datname      OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.datname)) 
	AND (_schemaname   OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.schemaname)) 
	AND (_relname      OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.relname)) 
	AND (_indexrelname OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.indexrelname)) 
	AND config.indexrelname IS NOT NULL
	AND TRUE
      UNION ALL
      --per table setting
      SELECT 2 AS priority, value FROM index_watch.config WHERE
        _key=config.key
        AND (_datname      OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.datname))
        AND (_schemaname   OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.schemaname))
        AND (_relname      OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.relname))
        AND config.relname IS NOT NULL
        AND config.indexrelname IS NULL
      UNION ALL
      --per schema setting
      SELECT 3 AS priority, value FROM index_watch.config WHERE
        _key=config.key
        AND (_datname      OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.datname))
        AND (_schemaname   OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.schemaname))
        AND config.schemaname IS NOT NULL
        AND config.relname IS NULL
      UNION ALL
      --per database setting
      SELECT 4 AS priority, value FROM index_watch.config WHERE
        _key=config.key
        AND (_datname      OPERATOR(pg_catalog.~) index_watch._pattern_convert(config.datname))
        AND config.datname IS NOT NULL
        AND config.schemaname IS NULL
      UNION ALL
      --global setting
      SELECT 5 AS priority, value FROM index_watch.config WHERE
        _key=config.key
        AND config.datname IS NULL
    ) AS _t
    WHERE value IS NOT NULL
    ORDER BY priority
    LIMIT 1;
    RETURN _value;
END;
$BODY$
LANGUAGE plpgsql STABLE;


CREATE OR REPLACE FUNCTION index_watch.set_or_replace_setting(_datname text, _schemaname text, _relname text, _indexrelname text, _key TEXT, _value text, _comment text)
RETURNS VOID AS
$BODY$
BEGIN
    PERFORM index_watch._check_structure_version();
    IF _datname IS NULL       THEN
      INSERT INTO index_watch.config (datname, schemaname, relname, indexrelname, key, value, comment) 
      VALUES (_datname, _schemaname, _relname, _indexrelname, _key, _value, _comment)
      ON CONFLICT (key) WHERE datname IS NULL DO UPDATE SET value=EXCLUDED.value, comment=EXCLUDED.comment;
    ELSIF _schemaname IS NULL THEN
      INSERT INTO index_watch.config (datname, schemaname, relname, indexrelname, key, value, comment) 
      VALUES (_datname, _schemaname, _relname, _indexrelname, _key, _value, _comment)
      ON CONFLICT (key, datname) WHERE schemaname IS NULL DO UPDATE SET value=EXCLUDED.value, comment=EXCLUDED.comment;
    ELSIF _relname IS NULL    THEN
      INSERT INTO index_watch.config (datname, schemaname, relname, indexrelname, key, value, comment) 
      VALUES (_datname, _schemaname, _relname, _indexrelname, _key, _value, _comment)
      ON CONFLICT (key, datname, schemaname) WHERE relname IS NULL DO UPDATE SET value=EXCLUDED.value, comment=EXCLUDED.comment;
    ELSIF _indexrelname IS NULL THEN
      INSERT INTO index_watch.config (datname, schemaname, relname, indexrelname, key, value, comment) 
      VALUES (_datname, _schemaname, _relname, _indexrelname, _key, _value, _comment)
      ON CONFLICT (key, datname, schemaname, relname) WHERE indexrelname IS NULL DO UPDATE SET value=EXCLUDED.value, comment=EXCLUDED.comment;
    ELSE
      INSERT INTO index_watch.config (datname, schemaname, relname, indexrelname, key, value, comment) 
      VALUES (_datname, _schemaname, _relname, _indexrelname, _key, _value, _comment)
      ON CONFLICT (key, datname, schemaname, relname, indexrelname) DO UPDATE SET value=EXCLUDED.value, comment=EXCLUDED.comment;    
    END IF;
    RETURN;
END;
$BODY$
LANGUAGE plpgsql;









CREATE OR REPLACE FUNCTION index_watch._remote_get_indexes_info(_datname name, _schemaname name, _relname name, _indexrelname name)
RETURNS TABLE(datname name, schemaname name, relname name, indexrelname name, indexsize BIGINT, estimated_tuples BIGINT) 
AS
$BODY$
BEGIN
    RETURN QUERY SELECT 
      _datname, _res.schemaname, _res.relname, _res.indexrelname, _res.indexsize,
      CASE WHEN relpages=0 THEN greatest(1, indexreltuples) ELSE (relsize::real/(relpages::real*current_setting('block_size')::real)*indexreltuples::real)::BIGINT END AS estimated_tuples
    FROM
    dblink('dbname='||pg_catalog.quote_ident(_datname),
    E'
      SELECT
        pg_stat_user_indexes.schemaname, 
        pg_stat_user_indexes.relname, 
        pg_stat_user_indexes.indexrelname,
        c1.relpages::BIGINT, 
        c2.reltuples::BIGINT AS indexreltuples, 
        pg_catalog.pg_relation_size(pg_stat_user_indexes.relid)::BIGINT AS relsize, 
        pg_catalog.pg_relation_size(pg_stat_user_indexes.indexrelid)::BIGINT AS indexsize        
      FROM pg_catalog.pg_stat_user_indexes 
      JOIN pg_catalog.pg_class AS c1 on c1.oid=pg_stat_user_indexes.relid
      JOIN pg_catalog.pg_class AS c2 on c2.oid=pg_stat_user_indexes.indexrelid
      WHERE NOT EXISTS (SELECT FROM pg_constraint WHERE pg_constraint.conindid=pg_stat_user_indexes.indexrelid and pg_constraint.contype=\'x\')
    ')
    AS _res(schemaname name, relname name, indexrelname name, relpages BIGINT, indexreltuples BIGINT, relsize BIGINT, indexsize BIGINT)
    WHERE 
    (_schemaname IS NULL   OR _res.schemaname=_schemaname)
    AND
    (_relname IS NULL      OR _res.relname=_relname)
    AND
    (_indexrelname IS NULL OR _res.indexrelname=_indexrelname)
    ;
END;
$BODY$
LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION index_watch._record_indexes_info(_datname name, _schemaname name, _relname name, _indexrelname name) 
RETURNS VOID 
AS
$BODY$
BEGIN
  INSERT INTO index_watch.index_history 
  (datname, schemaname, relname, indexrelname, indexsize, estimated_tuples)
  SELECT datname, schemaname, relname, indexrelname, indexsize, estimated_tuples
  FROM index_watch._remote_get_indexes_info(_datname, _schemaname, _relname, _indexrelname)
  WHERE
      (
        indexsize >= pg_size_bytes(index_watch.get_setting(datname, schemaname, relname, indexrelname, 'index_size_threshold'))
        AND 
        index_watch.get_setting(datname, schemaname, relname, indexrelname, 'skip')::boolean IS DISTINCT FROM TRUE
        --AND
        --index_watch.get_setting (for future configurability)
      )
    ;
END;
$BODY$
LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION index_watch._cleanup_old_records() RETURNS VOID AS
$BODY$
BEGIN
    --TODO replace with fast distinct implementation
    WITH 
        rels AS MATERIALIZED (SELECT DISTINCT datname, schemaname, relname, indexrelname FROM index_watch.index_history),
        age_limit AS MATERIALIZED (SELECT *, now()-index_watch.get_setting(datname,schemaname,relname,indexrelname,  'index_history_retention_period')::interval AS max_age FROM rels)
    DELETE FROM index_watch.index_history 
        USING age_limit 
        WHERE 
            index_history.datname=age_limit.datname 
            AND index_history.schemaname=age_limit.schemaname
            AND index_history.relname=age_limit.relname
            AND index_history.indexrelname=age_limit.indexrelname
            AND index_history.entry_timestamp<age_limit.max_age;
                        
    --TODO replace with fast distinct implementation
    WITH 
        rels AS MATERIALIZED (SELECT DISTINCT datname, schemaname, relname, indexrelname FROM index_watch.reindex_history),
        age_limit AS MATERIALIZED (SELECT *, now()-index_watch.get_setting(datname,schemaname,relname,indexrelname,  'reindex_history_retention_period')::interval AS max_age FROM rels)
    DELETE FROM index_watch.reindex_history 
        USING age_limit 
        WHERE 
            reindex_history.datname=age_limit.datname 
            AND reindex_history.schemaname=age_limit.schemaname
            AND reindex_history.relname=age_limit.relname
            AND reindex_history.indexrelname=age_limit.indexrelname
            AND reindex_history.entry_timestamp<age_limit.max_age;
    RETURN;
END;
$BODY$
LANGUAGE plpgsql;





CREATE OR REPLACE FUNCTION index_watch.get_index_bloat_estimates(_datname name)
RETURNS TABLE(datname name, schemaname name, relname name, indexrelname name, indexsize bigint, estimated_bloat real) 
AS
$BODY$
BEGIN
  PERFORM index_watch._check_structure_version();
  -- compare current index size per tuple with the best result since reindex value (including just after reindex data from reindex_history)
  RETURN QUERY 
  WITH 
    _last_reindex_values AS (
    SELECT
      DISTINCT ON (schemaname, relname, indexrelname)
      reindex_history.schemaname, reindex_history.relname, reindex_history.indexrelname, entry_timestamp, estimated_tuples, indexsize_after AS indexsize
      FROM index_watch.reindex_history 
      WHERE 
        reindex_history.datname = _datname
      ORDER BY schemaname, relname, indexrelname, entry_timestamp DESC
    ),
    _all_history_since_reindex AS (
       --last reindexed value
       SELECT _last_reindex_values.schemaname, _last_reindex_values.relname, _last_reindex_values.indexrelname, _last_reindex_values.entry_timestamp, _last_reindex_values.estimated_tuples, _last_reindex_values.indexsize
       FROM _last_reindex_values
       UNION ALL
       --all values since reindex or from start
       SELECT index_history.schemaname, index_history.relname, index_history.indexrelname, index_history.entry_timestamp, index_history.estimated_tuples, index_history.indexsize
       FROM index_watch.index_history
       LEFT JOIN _last_reindex_values USING (schemaname, relname, indexrelname)
       WHERE 
         index_history.datname = _datname
         AND index_history.entry_timestamp>=coalesce(_last_reindex_values.entry_timestamp, '-INFINITY'::timestamp)
    ),
    _best_values AS (
      --only valid best if reindex entry exists
      SELECT 
        DISTINCT ON (schemaname, relname, indexrelname) 
        _all_history_since_reindex.*
      FROM _all_history_since_reindex 
      JOIN _last_reindex_values USING (schemaname, relname, indexrelname)
      WHERE 
        _all_history_since_reindex.indexsize > pg_size_bytes(index_watch.get_setting(_datname, _all_history_since_reindex.schemaname, _all_history_since_reindex.relname, _all_history_since_reindex.indexrelname, 'minimum_reliable_index_size'))
      ORDER BY schemaname, relname, indexrelname, _all_history_since_reindex.estimated_tuples::real/_all_history_since_reindex.indexsize::real DESC
    ),
    _current_state AS (
      SELECT 
        DISTINCT ON (schemaname, relname, indexrelname) 
        _all_history_since_reindex.* 
      FROM _all_history_since_reindex
      ORDER BY schemaname, relname, indexrelname, entry_timestamp DESC
    ),
    _result AS (
       SELECT 
         _current_state.*, 
         --((_current_state.indexsize::real/_current_state.estimated_tuples::real)/(_best_values.indexsize::real/_best_values.estimated_tuples::real)) AS estimated_bloat
	case WHEN (_best_values.indexsize::real*_current_state.estimated_tuples::real=0) THEN 1000 ELSE ((_current_state.indexsize::real*_best_values.estimated_tuples::real)/(_best_values.indexsize::real*_current_state.estimated_tuples::real)) END AS estimated_bloat
       FROM _current_state
       LEFT JOIN _best_values USING (schemaname, relname, indexrelname)
    )
  SELECT _datname, _result.schemaname, _result.relname, _result.indexrelname, _result.indexsize, _result.estimated_bloat FROM _result;
END;
$BODY$
LANGUAGE plpgsql STRICT;





CREATE OR REPLACE FUNCTION index_watch._reindex_index(_datname name, _schemaname name, _relname name, _indexrelname name) 
RETURNS VOID 
AS
$BODY$
DECLARE
  _indexsize_before BIGINT;
  _indexsize_after  BIGINT;
  _timestamp        TIMESTAMP;
  _reindex_duration INTERVAL;
  _analyze_duration INTERVAL;
  _estimated_tuples BIGINT;
BEGIN

  --RAISE NOTICE 'working with %.%.% %', _datname, _schemaname, _relname, _indexrelname;

  --get initial index size
  SELECT indexsize INTO _indexsize_before
  FROM index_watch._remote_get_indexes_info(_datname, _schemaname, _relname, _indexrelname);
  --index doesn't exist anymore
  IF NOT FOUND THEN
    RETURN;
  END IF;
  
  --time to dance
  _timestamp := pg_catalog.clock_timestamp ();
  PERFORM dblink('dbname='||pg_catalog.quote_ident(_datname), 'REINDEX INDEX CONCURRENTLY '||pg_catalog.quote_ident(_schemaname)||'.'||pg_catalog.quote_ident(_indexrelname));
  _reindex_duration := pg_catalog.clock_timestamp ()-_timestamp;
  
  --analyze 
  _timestamp := clock_timestamp ();
  PERFORM dblink('dbname='||pg_catalog.quote_ident(_datname), 'ANALYZE '||pg_catalog.quote_ident(_schemaname)||'.'||pg_catalog.quote_ident(_relname));
  _analyze_duration := pg_catalog.clock_timestamp ()-_timestamp;

  --get final index size
  SELECT indexsize, estimated_tuples INTO STRICT _indexsize_after, _estimated_tuples
  FROM index_watch._remote_get_indexes_info(_datname, _schemaname, _relname, _indexrelname);
  
  --log reindex action
  INSERT INTO index_watch.reindex_history
  (datname, schemaname, relname, indexrelname, indexsize_before, indexsize_after, estimated_tuples, reindex_duration, analyze_duration)
  VALUES 
  (_datname, _schemaname, _relname, _indexrelname, _indexsize_before, _indexsize_after, _estimated_tuples, _reindex_duration, _analyze_duration);

  RETURN;
END;
$BODY$
LANGUAGE plpgsql STRICT;



CREATE OR REPLACE PROCEDURE index_watch.do_reindex(_datname name, _schemaname name, _relname name, _indexrelname name, _force BOOLEAN DEFAULT FALSE) 
AS
$BODY$
DECLARE
  _index RECORD;
BEGIN
  PERFORM index_watch._check_structure_version();
  FOR _index IN 
    SELECT datname, schemaname, relname, indexrelname, indexsize, estimated_bloat
    FROM index_watch.get_index_bloat_estimates(_datname)
    WHERE
      (_schemaname IS NULL OR schemaname=_schemaname)
      AND
      (_relname IS NULL OR relname=_relname)
      AND
      (_indexrelname IS NULL OR indexrelname=_indexrelname)
      AND
      (_force OR 
        (
          (
            estimated_bloat IS NULL OR 
            estimated_bloat >= index_watch.get_setting(datname, schemaname, relname, indexrelname, 'index_rebuild_scale_factor')::float
          )
          AND
          indexsize >= pg_size_bytes(index_watch.get_setting(datname, schemaname, relname, indexrelname, 'index_size_threshold'))
          AND 
          index_watch.get_setting(datname, schemaname, relname, indexrelname, 'skip')::boolean IS DISTINCT FROM TRUE
          --AND
          --index_watch.get_setting (for future configurability)
        )
      )
    LOOP
       PERFORM index_watch._reindex_index(_index.datname, _index.schemaname, _index.relname, _index.indexrelname);
       COMMIT;
    END LOOP;
  RETURN;
END;
$BODY$
LANGUAGE plpgsql;



CREATE OR REPLACE PROCEDURE index_watch.periodic(real_run BOOLEAN DEFAULT FALSE) AS
$BODY$
DECLARE 
  _datname NAME;
BEGIN
    PERFORM index_watch._check_structure_version();
    PERFORM index_watch._cleanup_old_records();
    COMMIT;

    FOR _datname IN 
      SELECT datname FROM pg_database 
      WHERE 
        NOT datistemplate 
        AND datallowconn 
        AND datname<>current_database()
        AND index_watch.get_setting(datname, NULL, NULL, NULL, 'skip')::boolean IS DISTINCT FROM TRUE
      ORDER BY datname
    LOOP
      PERFORM index_watch._record_indexes_info(_datname, NULL, NULL, NULL);
      COMMIT;
      IF (real_run) THEN      
        CALL index_watch.do_reindex(_datname, NULL, NULL, NULL, FALSE);
        COMMIT;
      END IF;
    END LOOP;
END;
$BODY$
LANGUAGE plpgsql;


        

        
      
      

