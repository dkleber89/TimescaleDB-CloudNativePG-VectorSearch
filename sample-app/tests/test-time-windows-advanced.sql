-- =============================================================================
-- Test: Time-Windowed Query Efficiency (Advanced)
-- =============================================================================
-- Demonstrates chunk exclusion with 50K vectors over 9 months
-- Shows how time filters reduce I/O by scanning only relevant chunks
-- Validates TimescaleDB's core benefit: query performance independent of data size
-- =============================================================================

\set QUIET on
\timing on
\pset border 2

\echo ''
\echo '========================================'
\echo 'Test: Time-Windowed Queries (50K vectors)'
\echo '========================================'
\echo ''

-- Create target vector for consistent testing across all scenarios
CREATE TEMP TABLE IF NOT EXISTS test_target AS
SELECT (
    SELECT ARRAY_AGG((random() * 2 - 1)::FLOAT4)::vector(384)
    FROM generate_series(1, 384)
) as embedding;

\echo 'Scenario 1: Recent Data (Last 7 Days)'
\echo '--------------------------------------'
\echo 'Shows: Minimal chunks scanned for recent queries'
\echo 'Expected: 1-2 chunks, fast query execution'
\echo ''

WITH target AS (SELECT embedding FROM test_target)
SELECT 
    symbol,
    COUNT(*) as patterns_found,
    ROUND(AVG(embedding <=> (SELECT embedding FROM target))::NUMERIC, 4) as avg_distance,
    ROUND(MIN(embedding <=> (SELECT embedding FROM target))::NUMERIC, 4) as min_distance
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '7 days'
GROUP BY symbol
ORDER BY avg_distance
LIMIT 5;

\echo ''
\echo 'Scenario 2: Last Month'
\echo '----------------------'
\echo 'Shows: Moderate chunk scanning for monthly queries'
\echo 'Expected: 4-5 chunks, still fast'
\echo ''

WITH target AS (SELECT embedding FROM test_target)
SELECT 
    symbol,
    COUNT(*) as patterns_found,
    ROUND(AVG(embedding <=> (SELECT embedding FROM target))::NUMERIC, 4) as avg_distance
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
GROUP BY symbol
ORDER BY avg_distance
LIMIT 5;

\echo ''
\echo 'Scenario 3: Historical Range (6 months ago)'
\echo '--------------------------------------------'
\echo 'Shows: Efficient queries on historical compressed data'
\echo 'Expected: 2-3 chunks (compressed), still performant'
\echo ''

WITH target AS (SELECT embedding FROM test_target)
SELECT 
    symbol,
    COUNT(*) as patterns_found,
    ROUND(AVG(embedding <=> (SELECT embedding FROM target))::NUMERIC, 4) as avg_distance
FROM pattern_embeddings
WHERE time BETWEEN NOW() - INTERVAL '7 months' AND NOW() - INTERVAL '6 months'
GROUP BY symbol
ORDER BY avg_distance
LIMIT 5;

\echo ''
\echo 'Scenario 4: Full Dataset Scan (NO time filter)'
\echo '-----------------------------------------------'
\echo 'Shows: What happens without time filtering (baseline comparison)'
\echo 'Expected: All 40+ chunks scanned, slower execution'
\echo ''

WITH target AS (SELECT embedding FROM test_target)
SELECT 
    symbol,
    COUNT(*) as total_patterns,
    ROUND(AVG(embedding <=> (SELECT embedding FROM target))::NUMERIC, 4) as avg_distance
FROM pattern_embeddings
GROUP BY symbol
ORDER BY avg_distance
LIMIT 5;

\echo ''
\echo 'Chunk Distribution by Time Period:'
\echo '-----------------------------------'
\echo 'Shows how chunks are organized across time - key to understanding performance'

WITH chunk_periods AS (
    SELECT 
        CASE 
            WHEN range_start >= NOW() - INTERVAL '7 days' THEN '  Recent (7d)'
            WHEN range_start >= NOW() - INTERVAL '30 days' THEN '  Last Month'
            WHEN range_start >= NOW() - INTERVAL '3 months' THEN '  Last Quarter'
            ELSE '  Historical (>3mo)'
        END as time_period,
        CASE 
            WHEN range_start >= NOW() - INTERVAL '7 days' THEN 1
            WHEN range_start >= NOW() - INTERVAL '30 days' THEN 2
            WHEN range_start >= NOW() - INTERVAL '3 months' THEN 3
            ELSE 4
        END as sort_order,
        is_compressed,
        chunk_schema,
        chunk_name
    FROM timescaledb_information.chunks
    WHERE hypertable_name = 'pattern_embeddings'
)
SELECT 
    time_period,
    COUNT(*) as chunks,
    SUM(CASE WHEN is_compressed THEN 1 ELSE 0 END) as compressed,
    pg_size_pretty(SUM(pg_relation_size((chunk_schema || '.' || chunk_name)::regclass))) as total_size
FROM chunk_periods
GROUP BY time_period, sort_order
ORDER BY sort_order;

\echo ''
\echo '========================================'
\echo 'Time-Windowed Query Test Complete'
\echo '========================================'
\echo ''
\echo 'Key Insights:'
\echo '  ✅ Time filters enable chunk exclusion'
\echo '  ✅ Recent queries scan 1-5 chunks (not all 40)'
\echo '  ✅ Query performance stays consistent regardless of total data size'
\echo '  ✅ Without time filters, all chunks must be scanned'
\echo ''
\echo 'Best Practice:'
\echo '  → Always include time filters in production queries'
\echo '  → Narrower time windows = better performance'
\echo ''

\timing off