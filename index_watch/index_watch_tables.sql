CREATE SCHEMA IF NOT EXISTS index_watch;

--history of performed REINDEX action
CREATE TABLE index_watch.reindex_history
(
  id bigserial primary key,
  entry_timestamp timestamptz not null default now(),
  datname name not null,
  schemaname name not null,
  relname name not null,
  indexrelname name not null,
  server_version_num integer not null default current_setting('server_version_num')::integer,
  indexsize_before BIGINT not null,
  indexsize_after BIGINT not null,
  estimated_tuples bigint not null,
  reindex_duration interval not null,
  analyze_duration interval not null
);
create index reindex_history_index on index_watch.reindex_history(datname, schemaname, relname, indexrelname, entry_timestamp);


--history of index sizes (not really neccessary to keep all this data but very useful for future analyzis of bloat trends
CREATE TABLE index_watch.index_history 
(
  id bigserial primary key,
  entry_timestamp timestamptz not null default now(),
  datname name not null,
  schemaname name not null,
  relname name not null,
  indexrelname name not null,
  server_version_num integer not null default current_setting('server_version_num')::integer,
  indexsize BIGINT not null,
  estimated_tuples BIGINT not null
);
create index index_history_index on index_watch.index_history(datname, schemaname, relname, indexrelname, entry_timestamp);

--settings table
CREATE TABLE index_watch.config
(
  id bigserial primary key,
  datname name,
  schemaname name,
  relname name,
  indexrelname name,
  key text not null,
  value text,
  comment text  
);
CREATE UNIQUE INDEX config_u1 on index_watch.config(key) WHERE datname IS NULL;
CREATE UNIQUE INDEX config_u2 on index_watch.config(key, datname) WHERE schemaname IS NULL;
CREATE UNIQUE INDEX config_u3 on index_watch.config(key, datname, schemaname) WHERE relname IS NULL;
CREATE UNIQUE INDEX config_u4 on index_watch.config(key, datname, schemaname, relname) WHERE indexrelname IS NULL;
CREATE UNIQUE INDEX config_u5 on index_watch.config(key, datname, schemaname, relname, indexrelname);
ALTER TABLE index_watch.config ADD CONSTRAINT inherit_check1 CHECK (indexrelname IS NULL OR indexrelname IS NOT NULL AND relname    IS NOT NULL);
ALTER TABLE index_watch.config ADD CONSTRAINT inherit_check2 CHECK (relname      IS NULL OR relname      IS NOT NULL AND schemaname IS NOT NULL);
ALTER TABLE index_watch.config ADD CONSTRAINT inherit_check3 CHECK (schemaname   IS NULL OR schemaname   IS NOT NULL AND datname    IS NOT NULL);

--DEFAULT GLOBAL settings
INSERT INTO index_watch.config (key, value, comment) VALUES 
('index_size_threshold', '10MB', 'ignore indexes under 100MB size unless forced entries found in history'),
('index_rebuild_scale_factor', '2', 'rebuild indexes by default estimated bloat over 2x'),
('minimum_reliable_index_size', '32kB', 'small indexes not reliable to use as gauge'),
('reindex_history_retention_period','10 years', 'reindex history default retention period'),
('index_history_retention_period', '1 year', 'index history default retention period')
;


--current version of table structure
CREATE TABLE index_watch.tables_version
(
	version smallint NOT NULL
);
CREATE UNIQUE INDEX tables_version_single_row ON  index_watch.tables_version((version IS NOT NULL));
INSERT INTO index_watch.tables_version VALUES(1);

