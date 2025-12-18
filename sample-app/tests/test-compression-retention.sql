-- =============================================================================
-- Test: Compression & Retention Policies
-- =============================================================================
-- Demonstrates TimescaleDB's automatic data lifecycle management
--
-- What this proves:
--   - Automatic compression of old data (saves 60-80% storage)
--   - Automatic deletion of expired data (retention policies)
--   - No manual intervention required
--   - Queries remain transparent on compressed chunks
-- =============================================================================

\set QUIET on
\pset border 2
\pset format wrapped

\echo ''
\echo '========================================'
\echo 'Test: Compression & Retention Policies'
\echo '========================================'
\echo ''

-- Show initial state - baseline before compression
\echo 'Step 1: Current table size and data distribution'
\echo '------------------------------------------------'

SELECT 
    COUNT(*) as total_vectors,
    COUNT(*) FILTER (WHERE time >= NOW() - INTERVAL '7 days') as recent_7d,
    COUNT(*) FILTER (WHERE time < NOW() - INTERVAL '7 days') as older_7d,
    pg_size_pretty(pg_total_relation_size('pattern_embeddings')) as total_size
FROM pattern_embeddings;

-- Show chunk details before compression - baseline metrics
\echo ''
\echo 'Step 2: Chunk details (before compression)'
\echo '-------------------------------------------'

SELECT 
    chunk_schema || '.' || chunk_name as chunk,
    range_start,
    range_end,
    is_compressed,
    pg_size_pretty(pg_relation_size((chunk_schema || '.' || chunk_name)::regclass)) as size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'pattern_embeddings'
ORDER BY range_start DESC
LIMIT 10;

-- Enable compression on hypertable and set compression policy
\echo ''
\echo 'Step 3: Enabling compression policy'
\echo '------------------------------------'

-- First, enable compression on the hypertable with segment and order configuration
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.compression_settings 
        WHERE hypertable_schema = 'public' AND hypertable_name = 'pattern_embeddings'
    ) THEN
        ALTER TABLE pattern_embeddings SET (
            timescaledb.compress,
            timescaledb.compress_segmentby = 'symbol',
            timescaledb.compress_orderby = 'time DESC'
        );
    END IF;
END $$;

-- Add compression policy - automatically compress chunks older than 7 days
SELECT add_compression_policy('pattern_embeddings', INTERVAL '7 days', if_not_exists => true);

\echo ''
\echo '✅ Compression policy enabled'
\echo '   - Chunks older than 7 days will be compressed'
\echo '   - Compression runs automatically in background'
\echo ''

-- Manually trigger compression for demonstration purposes
\echo 'Step 4: Manually compressing old chunks (for demo)'
\echo '---------------------------------------------------'

SELECT compress_chunk(chunk, if_not_compressed => true)
FROM show_chunks('pattern_embeddings', older_than => INTERVAL '7 days') AS chunk;

\echo ''
\echo '✅ Old chunks compressed'
\echo ''

-- Show compression results