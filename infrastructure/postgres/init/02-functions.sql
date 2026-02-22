-- =================================
-- 1. Checking indexes
-- =================================

CREATE OR REPLACE FUNCTION maintenance.find_useless_indexes(
    min_size_mb INTEGER DEFAULT 10
) RETURNS TABLE (
    table_schema TEXT,         -- Table schema.
    table_name TEXT,           -- Table name.
    index_name TEXT,           -- Index name.
    index_size TEXT,           -- Size of index, human-readable.
    scans_count BIGINT,        -- How many times was used.
    tuples_read BIGINT,        -- How many rows read via index.
    idx_scan BIGINT,           -- How many times index was scanned.
    value_density NUMERIC,     -- Ratio between 'usefull' and 'size'.
    stats_age INTERVAL,        -- Age of index statistics.
    server_uptime INTERVAL,    -- Server uptime.
    recommendation TEXT        -- Text description.
) AS $$
DECLARE
    stats_reset_time TIMESTAMP;
    server_start_time TIMESTAMP;
BEGIN
    -- Get statistics reset time
    SELECT stats_reset
    INTO stats_reset_time
    FROM pg_stat_database
    WHERE datname = current_database();

    -- Get server start time
    SELECT pg_postmaster_start_time()
    INTO server_start_time;

    RETURN QUERY
    SELECT
        s.schemaname::TEXT,
        s.relname::TEXT,
        s.indexrelname::TEXT,
        pg_size_pretty(pg_relation_size(s.indexrelid))::TEXT,
        s.idx_scan,
        s.idx_tup_read,
        s.idx_tup_fetch,

        -- Value density
        CASE
            WHEN s.idx_scan = 0 THEN 0
            ELSE ROUND(
                (s.idx_tup_fetch::numeric) /
                NULLIF(pg_relation_size(s.indexrelid)::numeric, 0),
                6
            )
        END AS value_density,

        now() - stats_reset_time AS stats_age,
        now() - server_start_time AS server_uptime,

        -- Recommendation
        CASE
            WHEN now() - stats_reset_time < interval '1 day'
                THEN '⚠️ Statistics too fresh. Review later.'
            WHEN s.idx_scan = 0
                THEN '⚠️ Candidate for removal (unused).'
            WHEN s.idx_scan < 10
                 AND pg_relation_size(s.indexrelid) > 100 * 1024^2
                THEN '❗ Large index, rarely used.'
            WHEN s.idx_scan < 100
                THEN '📊 Rarely used.'
            ELSE '✅ Actively used.'
        END::TEXT

    FROM pg_stat_user_indexes s
    JOIN pg_index i ON i.indexrelid = s.indexrelid
    WHERE pg_relation_size(s.indexrelid) > min_size_mb * 1024^2
      AND NOT i.indisprimary
      AND NOT i.indisunique
      AND NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            WHERE c.conindid = s.indexrelid
        )
    ORDER BY value_density ASC;

END;
$$ LANGUAGE plpgsql;

-- Comments
COMMENT ON COLUMN maintenance.find_useless_indexes.table_schema IS 'Schema of the table';
COMMENT ON COLUMN maintenance.find_useless_indexes.table_name IS 'Table name';
COMMENT ON COLUMN maintenance.find_useless_indexes.index_name IS 'Index name';
COMMENT ON COLUMN maintenance.find_useless_indexes.index_size IS 'Size of index, human-readable';
COMMENT ON COLUMN maintenance.find_useless_indexes.scans_count IS 'How many times index was used';
COMMENT ON COLUMN maintenance.find_useless_indexes.tuples_read IS 'Number of rows read via index';
COMMENT ON COLUMN maintenance.find_useless_indexes.idx_scan IS 'How many times index was scanned';
COMMENT ON COLUMN maintenance.find_useless_indexes.value_density IS 'Ratio between useful and size';
COMMENT ON COLUMN maintenance.find_useless_indexes.stats_age IS 'Age of index statistics';
COMMENT ON COLUMN maintenance.find_useless_indexes.server_uptime IS 'Server uptime';
COMMENT ON COLUMN maintenance.find_useless_indexes.recommendation IS 'Text recommendation for index maintenance';

-- =================================
-- 2. Find duplicates indexes (Exact duplicates.)
-- =================================

CREATE OR REPLACE FUNCTION maintenance.find_duplicate_indexes()
RETURNS TABLE (
    table_name TEXT,           -- Table name.
    index_name_1 TEXT,         -- Index №1 name.
    index_name_2 TEXT,         -- Index №2 name.
    index_size_1 TEXT,         -- Index №1 size.
    index_size_2 TEXT,         -- Index №2 size.
    index_definition_1 TEXT,   -- Index №1 expression.
    index_definition_2 TEXT    -- Index №2 expression.
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.relname::TEXT AS table_name,
        i1.indexrelid::regclass::TEXT AS index_name_1,
        i2.indexrelid::regclass::TEXT AS index_name_2,
        pg_size_pretty(pg_relation_size(i1.indexrelid)) AS index_size_1,
        pg_size_pretty(pg_relation_size(i2.indexrelid)) AS index_size_2,
        pg_get_indexdef(i1.indexrelid) AS index_definition_1,
        pg_get_indexdef(i2.indexrelid) AS index_definition_2
    FROM pg_index i1
    JOIN pg_index i2
        ON i1.indrelid = i2.indrelid                        -- Same table.
       AND i1.indexrelid < i2.indexrelid                    -- Not the same index.
       AND i1.indkey = i2.indkey                            -- Same columns.
       AND i1.indclass = i2.indclass                        -- Same operator.
       AND i1.indexprs IS NOT DISTINCT FROM i2.indexprs     -- Same expression (functional).
       AND i1.indpred IS NULL                               -- Same predicate (no partials).
       AND i2.indpred IS NULL
    JOIN pg_class t ON t.oid = i1.indrelid
    JOIN pg_class c1 ON c1.oid = i1.indexrelid
    JOIN pg_class c2 ON c2.oid = i2.indexrelid
    JOIN pg_am am1 ON am1.oid = c1.relam
    JOIN pg_am am2 ON am2.oid = c2.relam AND am1.amname = am2.amname
    ORDER BY table_name;
END;
$$ LANGUAGE plpgsql;
