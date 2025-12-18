-- =============================================================================
-- Extract Actual Query Timings from Test Suite
-- Runs the same queries as the tests and captures real execution times
-- Used by test harness to measure performance across different scenarios
-- =============================================================================

\set QUIET on
\timing off
\pset border 0
\pset tuples_only on

-- Test 1: Top-K Similarity Search
-- Measures pgvectorscale's ability to find K nearest neighbors efficiently
\echo 'TIMING_TEST_1_TOPK_START'
\timing on
WITH target AS (
    SELECT embedding 
    FROM pattern_embeddings 
    WHERE symbol = 'TSLA' 
    ORDER BY time DESC 
    LIMIT 1
)
SELECT 
    pe.symbol,
    ROUND((pe.embedding <=> t.embedding)::NUMERIC, 4) as distance,
    pe.time
FROM pattern_embeddings pe, target t
WHERE pe.time >= NOW() - INTERVAL '30 days'
ORDER BY distance
LIMIT 10;
\timing off
\echo 'TIMING_TEST_1_TOPK_END'

-- Test 2: Cross-Stock Pattern Correlation
-- Demonstrates multi-row similarity search with aggregation
\echo 'TIMING_TEST_2_CORR_START'
\timing on
WITH reference AS (
    SELECT embedding 
    FROM pattern_embeddings 
    WHERE symbol = 'NVDA' 
      AND time >= NOW() - INTERVAL '7 days'
    ORDER BY time DESC 
    LIMIT 1
)
SELECT 
    symbol,
    COUNT(*) as similar_patterns,
    ROUND(AVG(embedding <=> (SELECT embedding FROM reference))::NUMERIC, 4) as avg_similarity,
    ROUND(MIN(embedding <=> (SELECT embedding FROM reference))::NUMERIC, 4) as min_similarity
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
  AND symbol != 'NVDA'
  AND embedding <=> (SELECT embedding FROM reference) < 0.9
GROUP BY symbol
ORDER BY avg_similarity
LIMIT 10;
\timing off
\echo 'TIMING_TEST_2_CORR_END'

-- Test 3: Historical Pattern Matching
-- Shows performance on compressed historical data (6+ months old)
\echo 'TIMING_TEST_3_HIST_START'
\timing on
WITH reference AS (
    SELECT embedding 
    FROM pattern_embeddings 
    WHERE symbol = 'AAPL' 
      AND time >= NOW() - INTERVAL '180 days'
      AND time < NOW() - INTERVAL '170 days'
    ORDER BY time DESC 
    LIMIT 1
)
SELECT 
    symbol,
    COUNT(*) as matching_patterns,
    ROUND(AVG(embedding <=> (SELECT embedding FROM reference))::NUMERIC, 4) as avg_distance
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '180 days'
  AND embedding <=> (SELECT embedding FROM reference) < 0.85
GROUP BY symbol
ORDER BY avg_distance
LIMIT 10;
\timing off
\echo 'TIMING_TEST_3_HIST_END'

\set QUIET off
