-- =============================================================================
-- Metrics Collection Script
-- Captures key metrics from the test suite for final report generation
-- Runs after all tests complete to gather performance and data statistics
-- =============================================================================

\set QUIET on

-- Test 1: Time-Windowed Query Metrics
-- Measures query performance across different time windows to show chunk exclusion benefits
\echo '=== TEST 1 METRICS ==='

-- Recent query (7 days) - demonstrates minimal chunk scanning
\timing on
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'AAPL' ORDER BY time DESC LIMIT 1
)
SELECT COUNT(*) as recent_results
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '7 days'
  AND embedding <=> (SELECT embedding FROM target) < 0.9;
\timing off

-- Monthly query (30 days) - moderate chunk scanning
\timing on
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'AAPL' ORDER BY time DESC LIMIT 1
)
SELECT COUNT(*) as monthly_results
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
  AND embedding <=> (SELECT embedding FROM target) < 0.9;
\timing off

-- Quarterly query (90 days) - increased chunk scanning
\timing on
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'AAPL' ORDER BY time DESC LIMIT 1
)
SELECT COUNT(*) as quarterly_results
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '90 days'
  AND embedding <=> (SELECT embedding FROM target) < 0.9;
\timing off

-- Full scan (no time filter) - baseline: all chunks must be scanned
\timing on
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'AAPL' ORDER BY time DESC LIMIT 1
)
SELECT COUNT(*) as full_results
FROM pattern_embeddings
WHERE embedding <=> (SELECT embedding FROM target) < 0.9;
\timing off

-- Chunk distribution by time period - shows how data is organized across chunks
SELECT 
    COUNT(*) as total_chunks,
    COUNT(*) FILTER (WHERE time >= NOW() - INTERVAL '7 days') as recent_chunks,
    COUNT(*) FILTER (WHERE time >= NOW() - INTERVAL '30 days' AND time < NOW() - INTERVAL '7 days') as monthly_chunks,
    COUNT(*) FILTER (WHERE time >= NOW() - INTERVAL '90 days' AND time < NOW() - INTERVAL '30 days') as quarterly_chunks,
    COUNT(*) FILTER (WHERE time < NOW() - INTERVAL '90 days') as historical_chunks
FROM timescaledb_information.chunks
WHERE hypertable_name = 'pattern_embeddings';

\echo ''
\echo '=== TEST 2 METRICS ==='

-- Compression statistics - measures space savings from TimescaleDB compression
SELECT 
    COUNT(*) FILTER (WHERE is_compressed) as compressed_chunks,
    COUNT(*) FILTER (WHERE NOT is_compressed) as uncompressed_chunks,
    SUM(before_compression_total_bytes) as uncompressed_bytes,
    SUM(after_compression_total_bytes) as compressed_bytes,
    ROUND(100 - (SUM(after_compression_total_bytes)::NUMERIC / 
          NULLIF(SUM(before_compression_total_bytes), 0) * 100), 1) as space_saved_percent
FROM (
    SELECT 
        is_compressed,
        COALESCE(before_compression_total_bytes, 0) as before_compression_total_bytes,
        COALESCE(after_compression_total_bytes, 0) as after_compression_total_bytes
    FROM timescaledb_information.chunks
    LEFT JOIN chunk_compression_stats('pattern_embeddings') USING (chunk_schema, chunk_name)
    WHERE hypertable_name = 'pattern_embeddings'
) stats;

\echo ''
\echo '=== TEST 3 METRICS ==='

-- Vector search performance - measures pgvectorscale efficiency with DiskANN indexes
\timing on
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'AAPL' ORDER BY time DESC LIMIT 1
)
SELECT COUNT(*) as topk_results
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
ORDER BY embedding <=> (SELECT embedding FROM target)
LIMIT 10;
\timing off

-- Cross-stock pattern correlation - demonstrates real-world similarity search use case
\timing on
WITH reference AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'NVDA' AND time >= NOW() - INTERVAL '7 days' ORDER BY time DESC LIMIT 1
)
SELECT COUNT(DISTINCT symbol) as correlated_stocks
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
  AND symbol != 'NVDA'
  AND embedding <=> (SELECT embedding FROM reference) < 0.9;
\timing off

-- Total vectors and metadata - dataset statistics for context
SELECT 
    COUNT(*) as total_vectors,
    COUNT(DISTINCT symbol) as unique_stocks,
    COUNT(DISTINCT DATE(time)) as unique_dates,
    MIN(time) as earliest_data,
    MAX(time) as latest_data,
    EXTRACT(DAY FROM MAX(time) - MIN(time)) as days_span
FROM pattern_embeddings;

-- DiskANN index statistics - shows how pgvectorscale indexes are being used
SELECT 
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    idx_scan as times_used
FROM pg_stat_user_indexes
WHERE relname = 'pattern_embeddings'
  AND indexrelname LIKE '%diskann%'
ORDER BY indexrelname;

\set QUIET off
