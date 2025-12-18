-- =============================================================================
-- Test: Time-Windowed Query Efficiency
-- =============================================================================
-- Demonstrates how TimescaleDB hypertables optimize time-based queries
-- Uses EXPLAIN ANALYZE to show chunk exclusion in action
--
-- What this proves:
--   - Time-windowed queries scan fewer chunks (faster)
--   - Chunk exclusion reduces I/O and improves performance
--   - Query plans show which chunks are scanned
-- =============================================================================

\set QUIET on
\timing on
\pset border 2

\echo ''
\echo '========================================'
\echo 'Test: Time-Windowed Query Efficiency'
\echo '========================================'
\echo ''

-- Create a consistent target vector for all tests
CREATE TEMP TABLE test_target AS
SELECT (
    SELECT ARRAY_AGG((random() * 2 - 1)::FLOAT4)::vector(384)
    FROM generate_series(1, 384)
) as embedding;

\echo 'Step 1: Query recent data (last 7 days)'
\echo '----------------------------------------'
\echo 'EXPLAIN shows which chunks are scanned - expect 1-2 chunks'

EXPLAIN (ANALYZE, BUFFERS, SUMMARY OFF)
SELECT symbol, time, embedding <=> (SELECT embedding FROM test_target) as distance
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '7 days'
ORDER BY embedding <=> (SELECT embedding FROM test_target)
LIMIT 10;

\echo ''
\echo 'Step 2: Query medium window (last 30 days)'
\echo '--------------------------------------------'
\echo 'EXPLAIN shows increased chunks scanned - expect 4-5 chunks'

EXPLAIN (ANALYZE, BUFFERS, SUMMARY OFF)
SELECT symbol, time, embedding <=> (SELECT embedding FROM test_target) as distance
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
ORDER BY embedding <=> (SELECT embedding FROM test_target)
LIMIT 10;

\echo ''
\echo 'Step 3: Query