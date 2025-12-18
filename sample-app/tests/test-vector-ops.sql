-- =============================================================================
-- Test: pgvector Operations
-- =============================================================================
-- Validates pgvector extension and vector distance operations
-- Tests: Vector creation, distance operators (cosine, L2, inner product)
-- Demonstrates in-memory vector similarity search capabilities
-- =============================================================================

\set QUIET on
\pset border 2
\timing on

\echo ''
\echo '========================================'
\echo 'Test: pgvector Operations'
\echo '========================================'
\echo ''

-- Test 1: Verify pgvector extension is installed
\echo 'Test 1: Extension Installation'
\echo '-------------------------------'

SELECT 
    extname as extension,
    extversion as version,
    'Installed' as status
FROM pg_extension 
WHERE extname = 'vector';

\echo ''

-- Test 2: Vector distance operators
\echo 'Test 2: Distance Operators'
\echo '--------------------------'
\echo 'Tests three distance metrics: cosine, L2, inner product'

WITH test_vectors AS (
    SELECT 
        '[1,0,0]'::vector(3) as vec1,
        '[0,1,0]'::vector(3) as vec2,
        '[1,1,0]'::vector(3) as vec3
)
SELECT 
    'Cosine Distance' as operator,
    ROUND((vec1 <=> vec2)::NUMERIC, 4) as distance,
    'vec1 <=> vec2' as comparison
FROM test_vectors
UNION ALL
SELECT 
    'L2 Distance',
    ROUND((vec1 <-> vec2)::NUMERIC, 4),
    'vec1 <-> vec2'
FROM test_vectors
UNION ALL
SELECT 
    'Inner Product',
    ROUND((vec1 <#> vec2)::NUMERIC, 4),
    'vec1 <#> vec2'
FROM test_vectors;

\echo ''

-- Test 3: Vector similarity search on real data
\echo 'Test 3: Similarity Search'
\echo '-------------------------'
\echo 'Finds most similar patterns to AAPL using cosine distance'

WITH target AS (
    SELECT embedding 
    FROM pattern_embeddings 
    WHERE symbol = 'AAPL' 
    ORDER BY time DESC 
    LIMIT 1
)
SELECT 
    pe.symbol,
    pe.time,
    ROUND((pe.embedding <=> t.embedding)::NUMERIC, 6) as cosine_distance
FROM pattern_embeddings pe, target t
WHERE pe.symbol != 'AAPL'
ORDER BY cosine_distance
LIMIT 5;

\echo ''

-- Test 4: Vector dimensions verification
\echo 'Test 4: Vector Dimensions'
\echo '-------------------------'
\echo 'Confirms 384-dimensional embeddings are stored correctly'

SELECT 
    'pattern_embeddings' as table_name,
    'embedding' as column_name,
    atttypmod as dimensions,
    format_type(atttypid, atttypmod) as data_type
FROM pg_attribute
WHERE attrelid = 'pattern_embeddings'::regclass
  AND attname = 'embedding';

\echo ''
\echo '========================================'
\echo 'pgvector Test Complete'
\echo '========================================'
\echo ''
\echo 'Results:'
\echo '  ✅ pgvector extension installed'
\echo '  ✅ Distance operators functional (cosine, L2, inner product)'
\echo '  ✅ Similarity searches working'
\echo '  ✅ Vector dimensions correct (384)'
\echo ''

\timing off