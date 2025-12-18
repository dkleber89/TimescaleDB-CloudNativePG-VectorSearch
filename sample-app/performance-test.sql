-- =============================================================================
-- Stock Pattern Recognition System - Performance Benchmark
-- =============================================================================
-- Demonstrates pgvectorscale's StreamingDiskANN performance advantage
-- Compares sequential scan vs DiskANN index across different dataset sizes
-- 
-- Key Improvements:
--   - Fixed timestamp generation (no conflicts)
--   - Direct vector search (no subquery overhead)
--   - Tests true approximate nearest neighbor (ANN) workload
--
-- Test Strategy:
--   1. Baseline with existing 1.8K vectors
--   2. Scale to 5K, 10K, 25K, 50K vectors
--   3. Compare Sequential Scan vs diskann Index
--   4. Use direct vector literal for realistic ANN query
-- =============================================================================

\timing on

-- Create temporary table to store benchmark results
DROP TABLE IF EXISTS benchmark_results;
CREATE TEMP TABLE benchmark_results (
    test_id SERIAL PRIMARY KEY,
    dataset_size INTEGER NOT NULL,
    index_type TEXT NOT NULL,
    execution_time_ms NUMERIC(10,3) NOT NULL,
    test_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Create target vector (random 384-dim vector for consistent testing)
-- =============================================================================
-- Use same target vector across all tests for fair comparison

CREATE TEMP TABLE target_vector AS
SELECT (
    SELECT ARRAY_AGG((random() * 2 - 1)::FLOAT4)::vector(384)
    FROM generate_series(1, 384)
) as embedding;

\echo '========================================'
\echo 'Performance Benchmark Starting'
\echo '========================================'

-- =============================================================================
-- Helper function to measure query time with direct vector search
-- =============================================================================
-- Measures execution time for vector similarity search queries

CREATE OR REPLACE FUNCTION measure_query_time(use_limit INTEGER DEFAULT 10) 
RETURNS NUMERIC AS $$
DECLARE
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    result RECORD;
    target_vec vector(384);
BEGIN
    -- Get target vector
    SELECT embedding INTO target_vec FROM target_vector;
    
    start_time := clock_timestamp();
    
    -- Run the query with direct vector comparison (uses index if available)
    FOR result IN
        SELECT pe.symbol, pe.embedding <=> target_vec as distance
        FROM pattern_embeddings pe
        ORDER BY pe.embedding <=> target_vec  -- Cosine distance ordering
        LIMIT use_limit
    LOOP
        -- Just iterate to execute the query
    END LOOP;
    
    end_time := clock_timestamp();
    
    RETURN EXTRACT(MILLISECOND FROM (end_time - start_time));
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- PHASE 1: Baseline Test (1,800 vectors - existing data)
-- =============================================================================
-- Establishes baseline performance with current dataset

\echo ''
\echo '========================================'
\echo 'PHASE 1: Testing 1,800 vectors (baseline)'
\echo '========================================'

DO $$
DECLARE
    vector_count INTEGER;
    seq_time NUMERIC;
    index_time NUMERIC;
BEGIN
    SELECT COUNT(*) INTO vector_count FROM pattern_embeddings;
    RAISE NOTICE 'Current dataset size: % vectors', vector_count;
    
    -- Test 1A: Sequential scan (no index) - baseline performance
    RAISE NOTICE 'Test 1A: Sequential scan...';
    DROP INDEX IF EXISTS idx_pattern_embeddings_diskann_cosine;
    PERFORM pg_sleep(0.5);  -- Let query planner stats settle
    
    seq_time := measure_query_time(10);
    INSERT INTO benchmark_results (dataset_size, index_type, execution_time_ms)
    VALUES (vector_count, 'Sequential Scan', seq_time);
    RAISE NOTICE '  Result: %.2f ms', seq_time;
    
    -- Test 1B: With diskann index - shows index benefit
    RAISE NOTICE 'Test 1B: diskann index...';
    CREATE INDEX idx_pattern_embeddings_diskann_cosine 
        ON pattern_embeddings 
        USING diskann (embedding vector_cosine_ops)
        WITH (num_neighbors = 50, search_list_size = 100, max_alpha = 1.2, num_dimensions = 384, num_bits_per_dimension = 2);
    
    PERFORM pg_sleep(0.5);
    index_time := measure_query_time(10);
    INSERT INTO benchmark_results (dataset_size, index_type, execution_time_ms)
    VALUES (vector_count, 'diskann Index', index_time);
    RAISE NOTICE '  Result: %.2f ms', index_time;
END $$;

-- =============================================================================
-- PHASE 2-5: Generate Synthetic Data and Test (5K, 10K, 25K, 50K)
-- =============================================================================
-- Scales dataset and measures performance improvement with DiskANN index

DO $$
DECLARE
    target_sizes INTEGER[] := ARRAY[5000, 10000, 25000, 50000];
    target_size INTEGER;
    current_size INTEGER;
    vectors_needed INTEGER;
    stock_symbols TEXT[] := ARRAY['AAPL', 'TSLA', 'NVDA', 'MSFT', 'GOOGL', 'AMZN', 'META', 'AMD', 'INTC', 'NFLX'];
    base_time TIMESTAMPTZ;
    seq_time NUMERIC;
    index_time NUMERIC;
    time_offset BIGINT;
BEGIN
    FOREACH target_size IN ARRAY target_sizes
    LOOP
        SELECT COUNT(*) INTO current_size FROM pattern_embeddings;
        vectors_needed := target_size - current_size;
        
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'PHASE: Scaling to % vectors', target_size;
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Generating % synthetic vectors...', vectors_needed;
        
        -- Generate synthetic vectors with unique timestamps
        base_time := NOW() - INTERVAL '500 days';
        
        INSERT INTO pattern_embeddings (time, symbol, embedding, window_hours, volatility, trend)
        SELECT 
            -- Use current_size + series_num to ensure unique timestamps
            base_time + ((current_size + series_num) || ' seconds')::INTERVAL,
            stock_symbols[(series_num % 10) + 1],
            -- Generate random 384-dim vector for realistic testing
            (
                SELECT ARRAY_AGG((random() * 2 - 1)::FLOAT4)::vector(384)
                FROM generate_series(1, 384)
            ),
            24,
            random() * 2,
            (random() - 0.5) * 0.0001
        FROM generate_series(1, vectors_needed) AS series_num
        ON CONFLICT (time, symbol, window_hours) DO NOTHING;
        
        SELECT COUNT(*) INTO current_size FROM pattern_embeddings;
        RAISE NOTICE 'Generation complete. Actual size: % vectors', current_size;
        
        IF current_size < target_size * 0.95 THEN
            RAISE WARNING 'Expected %, got % (%.1f%% of target)', 
                target_size, current_size, (current_size::FLOAT / target_size * 100);
        END IF;
        
        -- Test A: Sequential scan (baseline at this scale)
        RAISE NOTICE 'Test A: Sequential scan...';
        DROP INDEX IF EXISTS idx_pattern_embeddings_diskann_cosine;
        PERFORM pg_sleep(0.5);
        
        seq_time := measure_query_time(10);
        INSERT INTO benchmark_results (dataset_size, index_type, execution_time_ms)
        VALUES (current_size, 'Sequential Scan', seq_time);
        RAISE NOTICE '  Result: %.2f ms', seq_time;
        
        -- Test B: diskann index (shows performance advantage at scale)
        RAISE NOTICE 'Test B: diskann index...';
        CREATE INDEX idx_pattern_embeddings_diskann_cosine 
            ON pattern_embeddings 
            USING diskann (embedding vector_cosine_ops)
            WITH (num_neighbors = 50, search_list_size = 100, max_alpha = 1.2, num_dimensions = 384, num_bits_per_dimension = 2);
        
        PERFORM pg_sleep(0.5);
        index_time := measure_query_time(10);
        INSERT INTO benchmark_results (dataset_size, index_type, execution_time_ms)
        VALUES (current_size, 'diskann Index', index_time);
        RAISE NOTICE '  Result: %.2f ms', index_time;
        
    END LOOP;
END $$;

-- =============================================================================
-- Display Results and Analysis
-- =============================================================================

\echo ''
\echo '========================================='
\echo 'PERFORMANCE BENCHMARK RESULTS'
\echo '========================================='

-- Summary table with actual dataset sizes - shows speedup factor
SELECT 
    dataset_size as "Vectors",
    MAX(CASE WHEN index_type = 'Sequential Scan' THEN ROUND(execution_time_ms, 2) END) as "Seq Scan (ms)",
    MAX(CASE WHEN index_type = 'diskann Index' THEN ROUND(execution_time_ms, 2) END) as "diskann (ms)",
    ROUND(
        MAX(CASE WHEN index_type = 'Sequential Scan' THEN execution_time_ms END) / 
        NULLIF(MAX(CASE WHEN index_type = 'diskann Index' THEN execution_time_ms END), 0),
        2
    ) as "Speedup"
FROM benchmark_results
GROUP BY dataset_size
ORDER BY dataset_size;

\echo ''
\echo 'Analysis:'
SELECT 
    CASE 
        WHEN AVG(CASE WHEN index_type = 'diskann Index' THEN execution_time_ms END) < 
             AVG(CASE WHEN index_type = 'Sequential Scan' THEN execution_time_ms END)
        THEN '  ✓ diskann provides performance advantage at scale'
        ELSE '  ℹ Dataset may be too small to see diskann benefit'
    END as observation
FROM benchmark_results
WHERE dataset_size >= 25000;

\echo ''

-- Show storage metrics - demonstrates index compression efficiency
SELECT 
    pg_size_pretty(pg_relation_size('idx_pattern_embeddings_diskann_cosine')) as "Index Size",
    pg_size_pretty(pg_total_relation_size('pattern_embeddings')) as "Table+Index Size",
    (SELECT COUNT(*) FROM pattern_embeddings) as "Final Vector Count"
;

-- Cleanup helper function
DROP FUNCTION IF EXISTS measure_query_time(INTEGER);

\echo ''
\echo '========================================='
\echo 'Benchmark Complete!'
\echo '========================================='
\echo ''
\echo 'To restore original dataset:'
\echo '  kubectl exec -it timescaledb-cluster-1 -n timescaledb -- \'
\echo '    psql -U postgres -d app -c "DROP TABLE pattern_embeddings CASCADE; DROP TABLE stock_prices CASCADE;"'
\echo ''
\echo '  Then re-run setup scripts (schema, seed-data, create-embeddings, indexes)'
\echo ''

\timing off