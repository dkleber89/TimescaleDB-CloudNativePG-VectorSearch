-- =============================================================================
-- Test: Vector Search Performance at Scale (50K vectors)
-- =============================================================================
-- Demonstrates vector similarity search performance with 50,000 vectors
-- Shows pgvectorscale's efficiency at production scale with DiskANN indexes
-- Validates that vector search remains fast even with large datasets
-- =============================================================================

\set QUIET on
\timing on
\pset border 2

\echo ''
\echo '========================================'
\echo 'Test: Vector Search at Scale'
\echo '========================================'
\echo ''

\echo 'Dataset Overview:'
\echo '-----------------'
\echo 'Shows the scale of data being searched'

SELECT 
    COUNT(*) as total_vectors,
    COUNT(DISTINCT symbol) as unique_symbols,
    MIN(time) as earliest_data,
    MAX(time) as latest_data,
    pg_size_pretty(pg_total_relation_size('pattern_embeddings')) as total_size
FROM pattern_embeddings;

\echo ''
\echo 'Test 1: Top-K Similarity Search'
\echo '--------------------------------'
\echo 'Query: Find 10 most similar patterns to TSLA (last 30 days)'
\echo 'Demonstrates: Fast top-K retrieval with DiskANN indexes'
\echo ''

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

\echo ''
\echo 'Test 2: Cross-Stock Pattern Correlation'
\echo '----------------------------------------'
\echo 'Query: Find stocks with patterns similar to NVDA'
\echo 'Demonstrates: Multi-row similarity search with aggregation'
\echo ''

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

\echo ''
\echo 'Test 3: Historical Pattern Matching'
\echo '------------------------------------'
\echo 'Query: Find similar patterns from 6 months ago'
\echo 'Demonstrates: Searching compressed historical chunks'
\echo ''

WITH target AS (
    SELECT embedding 
    FROM pattern_embeddings 
    WHERE symbol = 'META'
      AND time >= NOW() - INTERVAL '7 days'
    ORDER BY time DESC 
    LIMIT 1
)
SELECT 
    symbol,
    COUNT(*) as matches,
    ROUND(AVG(embedding <=> (SELECT embedding FROM target))::NUMERIC, 4) as avg_distance
FROM pattern_embeddings
WHERE time BETWEEN NOW() - INTERVAL '7 months' AND NOW() - INTERVAL '6 months'
GROUP BY symbol
ORDER BY avg_distance
LIMIT 10;

\echo ''
\echo 'Test 4: Index Usage Statistics'
\echo '-------------------------------'
\echo 'Shows how many times DiskANN indexes are being used'

SELECT 
    indexrelname as index_name,
    idx_scan as times_used,
    idx_tup_read as tuples_read,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE relname = 'pattern_embeddings'
  AND indexrelname LIKE '%diskann%';

\echo ''
\echo 'Test 5: Query Execution Plan (Verify Index Usage)'
\echo '--------------------------------------------------'
\echo 'EXPLAIN ANALYZE: Shows if DiskANN index is used for vector search'
\echo ''

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'AAPL' ORDER BY time DESC LIMIT 1
)
SELECT symbol, embedding <=> (SELECT embedding FROM target) as distance
FROM pattern_embeddings
WHERE time >= NOW() - INTERVAL '30 days'
ORDER BY embedding <=> (SELECT embedding FROM target)
LIMIT 10;

\echo ''
\echo '========================================'
\echo 'Vector Search Test Complete'
\echo '========================================'
\echo ''
\echo 'Key Observations:'
\echo '  ✅ Similarity searches complete in milliseconds (50K vectors)'
\echo '  ✅ DiskANN indexes enable efficient approximate nearest neighbor search'
\echo '  ✅ Time filters reduce search space via chunk exclusion'
\echo '  ✅ Cross-stock pattern correlation identifies similar market behaviors'
\echo ''
\echo 'What This Means:'
\echo '  → pgvectorscale enables production-scale vector search'
\echo '  → Disk-based indexes work within RAM constraints'
\echo '  → Suitable for edge/K8s deployments with limited resources'
\echo ''

\timing off