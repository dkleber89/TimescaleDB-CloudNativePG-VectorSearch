-- =============================================================================
-- Generate Large Dataset for Capability Testing
-- =============================================================================
-- Creates 50,000 vectors distributed over 9 months
-- Simulates realistic time-series data with multiple stock symbols
-- Used to test TimescaleDB chunking, compression, and pgvectorscale indexing
-- =============================================================================

\set QUIET on
\timing on

\echo ''
\echo '========================================'
\echo 'Generating 50K Vector Dataset'
\echo '========================================'
\echo ''

DO $$
DECLARE
    current_count INTEGER;
    vectors_needed INTEGER;
    -- 10 tech stocks for realistic market simulation
    stock_symbols TEXT[] := ARRAY['AAPL', 'TSLA', 'NVDA', 'MSFT', 'GOOGL', 'AMZN', 'META', 'AMD', 'INTC', 'NFLX'];
    start_date TIMESTAMPTZ;
    end_date TIMESTAMPTZ;
    total_seconds BIGINT;
    batch_size INTEGER := 1000;
    batches_needed INTEGER;
    current_batch INTEGER := 0;
BEGIN
    -- Check current size to avoid re-generating if dataset exists
    SELECT COUNT(*) INTO current_count FROM pattern_embeddings;
    vectors_needed := 50000 - current_count;
    
    IF vectors_needed <= 0 THEN
        RAISE NOTICE 'Dataset already has % vectors (>= 50K target)', current_count;
        RETURN;
    END IF;
    
    RAISE NOTICE 'Current vectors: %', current_count;
    RAISE NOTICE 'Generating % additional vectors...', vectors_needed;
    RAISE NOTICE '';
    
    -- Time distribution: 9 months ago to now (creates realistic historical data)
    start_date := NOW() - INTERVAL '9 months';
    end_date := NOW();
    total_seconds := EXTRACT(EPOCH FROM (end_date - start_date))::BIGINT;
    
    batches_needed := CEIL(vectors_needed::NUMERIC / batch_size);
    
    -- Generate in batches for progress tracking and memory efficiency
    FOR current_batch IN 1..batches_needed LOOP
        INSERT INTO pattern_embeddings (time, symbol, embedding, window_hours, volatility, trend)
        SELECT 
            -- Distribute evenly across 9 months
            start_date + (((current_batch - 1) * batch_size + series_num) * total_seconds / 50000.0 || ' seconds')::INTERVAL,
            stock_symbols[(series_num % 10) + 1],
            -- Generate random 384-dim vector
            (
                SELECT ARRAY_AGG((random() * 2 - 1)::FLOAT4)::vector(384)
                FROM generate_series(1, 384)
            ),
            24,
            random() * 2,
            (random() - 0.5) * 0.0001
        FROM generate_series(1, LEAST(batch_size, vectors_needed - (current_batch - 1) * batch_size)) AS series_num
        ON CONFLICT (time, symbol, window_hours) DO NOTHING;
        
        -- Progress update every 10 batches for visibility
        IF current_batch % 10 = 0 THEN
            RAISE NOTICE 'Progress: %/%  batches (~% vectors)', 
                current_batch, batches_needed, current_batch * batch_size;
        END IF;
    END LOOP;
    
    SELECT COUNT(*) INTO current_count FROM pattern_embeddings;
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Dataset Generation Complete';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total vectors: %', current_count;
    RAISE NOTICE 'Time range: 9 months';
    RAISE NOTICE '';
END $$;

-- Show data distribution by month - validates even distribution
\echo 'Data Distribution by Month:'
\echo '---------------------------'

SELECT 
    to_char(date_trunc('month', time), 'YYYY-MM') as month,
    COUNT(*) as vectors,
    COUNT(DISTINCT symbol) as stocks
FROM pattern_embeddings
GROUP BY date_trunc('month', time)
ORDER BY month;

\echo ''

-- Show total size and chunk count - demonstrates TimescaleDB chunking
\echo 'Storage Statistics:'
\echo '-------------------'

SELECT 
    COUNT(*) as total_vectors,
    COUNT(DISTINCT symbol) as unique_symbols,
    pg_size_pretty(pg_total_relation_size('pattern_embeddings')) as total_size,
    (SELECT COUNT(*) FROM timescaledb_information.chunks 
     WHERE hypertable_name = 'pattern_embeddings') as total_chunks
FROM pattern_embeddings;

\echo ''
\echo '========================================'
\echo 'Dataset Ready for Capability Tests'
\echo '========================================'
\echo ''

\timing off