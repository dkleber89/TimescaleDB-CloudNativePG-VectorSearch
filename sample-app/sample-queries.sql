-- =============================================================================
-- Stock Pattern Recognition System - Sample Queries
-- =============================================================================
-- Demonstrates practical use cases for vector similarity search in stock analysis
-- Shows how to combine TimescaleDB time-series with pgvector similarity search
-- =============================================================================

-- =============================================================================
-- QUERY 1: Find stocks with similar recent price patterns
-- =============================================================================
-- Use case: "Which stocks are moving like TSLA right now?"
-- Demonstrates: Real-time pattern matching using vector similarity

WITH target_pattern AS (
    SELECT embedding, time, volatility, trend
    FROM pattern_embeddings
    WHERE symbol = 'TSLA'
    ORDER BY time DESC
    LIMIT 1
)
SELECT 
    pe.symbol,
    pe.time,
    ROUND(pe.volatility, 4) as volatility,
    ROUND(pe.trend, 6) as trend,
    ROUND((pe.embedding <=> tp.embedding)::NUMERIC, 6) as cosine_distance,
    ROUND((1 - (pe.embedding <=> tp.embedding))::NUMERIC, 6) as similarity_score
FROM pattern_embeddings pe, target_pattern tp
WHERE pe.symbol != 'TSLA'  -- Exclude target stock itself
  AND pe.time >= NOW() - INTERVAL '24 hours'  -- Recent patterns only (TimescaleDB chunk exclusion)
ORDER BY pe.embedding <=> tp.embedding  -- Cosine distance (lower = more similar)
LIMIT 5;

-- =============================================================================
-- QUERY 2: Historical pattern matching
-- =============================================================================
-- Use case: "Find past instances where NVDA moved like it's moving now"
-- Demonstrates: Predictive analysis by finding similar historical patterns

WITH current_pattern AS (
    SELECT embedding
    FROM pattern_embeddings
    WHERE symbol = 'NVDA'
    ORDER BY time DESC
    LIMIT 1
)
SELECT 
    pe.symbol,
    pe.time,
    TO_CHAR(pe.time, 'YYYY-MM-DD HH24:MI') as pattern_time,
    ROUND(pe.volatility, 4) as volatility,
    ROUND((pe.embedding <=> cp.embedding)::NUMERIC, 6) as distance,
    -- Calculate what happened 24 hours after this pattern (outcome analysis)
    (
        SELECT ROUND(((sp_after.close - sp_before.close) / sp_before.close * 100)::NUMERIC, 2)
        FROM stock_prices sp_before, stock_prices sp_after
        WHERE sp_before.symbol = pe.symbol 
          AND sp_before.time = pe.time
          AND sp_after.symbol = pe.symbol
          AND sp_after.time = pe.time + INTERVAL '24 hours'
        LIMIT 1
    ) as price_change_24h_pct
FROM pattern_embeddings pe, current_pattern cp
WHERE pe.symbol = 'NVDA'
  AND pe.time < NOW() - INTERVAL '7 days'  -- Look at historical patterns (older data)
ORDER BY pe.embedding <=> cp.embedding  -- Find most similar historical patterns
LIMIT 10;

-- =============================================================================
-- QUERY 3: Cross-stock correlation analysis
-- =============================================================================
-- Use case: "Find stocks that consistently move together"
-- Demonstrates: Multi-stock pattern correlation using vector similarity

WITH aapl_patterns AS (
    SELECT time, embedding
    FROM pattern_embeddings
    WHERE symbol = 'AAPL'
      AND time >= NOW() - INTERVAL '7 days'  -- Recent patterns only
)
SELECT 
    pe.symbol,
    COUNT(*) as matching_patterns,
    ROUND(AVG((pe.embedding <=> ap.embedding))::NUMERIC, 6) as avg_distance,
    ROUND(AVG(pe.volatility), 4) as avg_volatility
FROM pattern_embeddings pe
JOIN aapl_patterns ap ON pe.time = ap.time  -- Same time windows
WHERE pe.symbol != 'AAPL'
  AND pe.time >= NOW() - INTERVAL '7 days'
GROUP BY pe.symbol
ORDER BY avg_distance ASC  -- Stocks with most similar patterns to AAPL
LIMIT 5;

-- =============================================================================
-- QUERY 4: Volatility-based pattern search
-- =============================================================================
-- Use case: "Find high-volatility stocks with similar momentum"
-- Demonstrates: Filtering by metadata before vector similarity search

WITH high_vol_stocks AS (
    -- Find stocks with above-average volatility (1.5x mean)
    SELECT DISTINCT symbol
    FROM pattern_embeddings
    WHERE time >= NOW() - INTERVAL '24 hours'
      AND volatility > (
          SELECT AVG(volatility) * 1.5 
          FROM pattern_embeddings 
          WHERE time >= NOW() - INTERVAL '24 hours'
      )
),
target AS (
    SELECT embedding
    FROM pattern_embeddings
    WHERE symbol = 'AMD'
    ORDER BY time DESC
    LIMIT 1
)
SELECT 
    pe.symbol,
    ROUND(pe.volatility, 4) as volatility,
    ROUND(pe.trend, 6) as trend,
    ROUND((pe.embedding <=> t.embedding)::NUMERIC, 6) as distance
FROM pattern_embeddings pe, target t
WHERE pe.symbol IN (SELECT symbol FROM high_vol_stocks)  -- Filter by volatility first
  AND pe.time >= NOW() - INTERVAL '24 hours'
ORDER BY pe.embedding <=> t.embedding  -- Then find similar patterns
LIMIT 5;

-- =============================================================================
-- QUERY 5: Time-series + vector hybrid query
-- =============================================================================
-- Use case: "Find similar patterns during specific market conditions"
-- Demonstrates: Combining time-series filtering with vector similarity

WITH morning_patterns AS (
    -- Filter by time of day (market open hours 9-12)
    SELECT symbol, time, embedding, volatility
    FROM pattern_embeddings
    WHERE EXTRACT(HOUR FROM time) BETWEEN 9 AND 12  -- Market open hours
      AND time >= NOW() - INTERVAL '7 days'
),
reference_pattern AS (
    SELECT embedding
    FROM pattern_embeddings
    WHERE symbol = 'MSFT'
    ORDER BY time DESC
    LIMIT 1
)
SELECT 
    mp.symbol,
    COUNT(*) as num_similar_patterns,
    ROUND(AVG((mp.embedding <=> rp.embedding))::NUMERIC, 6) as avg_similarity,
    ROUND(AVG(mp.volatility), 4) as avg_morning_volatility
FROM morning_patterns mp, reference_pattern rp
WHERE mp.symbol != 'MSFT'
GROUP BY mp.symbol
HAVING AVG((mp.embedding <=> rp.embedding)) < 0.3  -- Similarity threshold (high similarity)
ORDER BY avg_similarity ASC;

-- =============================================================================
-- QUERY 6: Performance verification - Index scan vs sequential scan
-- =============================================================================
-- Demonstrates: DiskANN index usage in query execution plan
-- Shows how pgvectorscale optimizes vector similarity search

EXPLAIN (ANALYZE, BUFFERS) 
WITH target AS (
    SELECT embedding FROM pattern_embeddings WHERE symbol = 'GOOGL' ORDER BY time DESC LIMIT 1
)
SELECT pe.symbol, pe.time, pe.embedding <=> t.embedding as distance
FROM pattern_embeddings pe, target t
ORDER BY pe.embedding <=> t.embedding  -- Uses DiskANN index if available
LIMIT 10;

-- =============================================================================
-- Statistics Summary
-- =============================================================================
-- Shows overall dataset and infrastructure metrics

SELECT 
    'Total Patterns' as metric,
    COUNT(*)::TEXT as value
FROM pattern_embeddings
UNION ALL
SELECT 
    'Unique Stocks',
    COUNT(DISTINCT symbol)::TEXT
FROM pattern_embeddings
UNION ALL
SELECT 
    'Date Range',
    TO_CHAR(MIN(time), 'YYYY-MM-DD') || ' to ' || TO_CHAR(MAX(time), 'YYYY-MM-DD')
FROM pattern_embeddings
UNION ALL
SELECT 
    'Avg Volatility',
    ROUND(AVG(volatility)::NUMERIC, 4)::TEXT
FROM pattern_embeddings
UNION ALL
SELECT 
    'Index Size (cosine)',
    pg_size_pretty(pg_relation_size('idx_pattern_embeddings_diskann_cosine'))
UNION ALL
SELECT 
    'Index Size (L2)',
    pg_size_pretty(pg_relation_size('idx_pattern_embeddings_diskann_l2'))
UNION ALL
SELECT 
    'Table Size',
    pg_size_pretty(pg_total_relation_size('pattern_embeddings'));

-- =============================================================================
-- End of Sample Queries
-- =============================================================================
-- 
-- Key Takeaways:
-- 1. Vector similarity enables pattern-based stock discovery
-- 2. Combining time-series and vector search unlocks powerful analytics
-- 3. StreamingDiskANN (diskann) provides efficient large-scale search
-- 4. Cosine distance works well for pattern matching (scale-invariant)
-- 5. TimescaleDB chunk exclusion + pgvectorscale indexes = fast queries
-- 
-- Production Considerations:
-- - Use actual ML embeddings (LSTM, Transformers) instead of synthetic
-- - Implement real-time embedding updates as new data arrives
-- - Add caching layer for frequently accessed patterns
-- - Monitor index performance and tune parameters as data grows
-- - Consider hybrid queries combining time-series and vector filters
-- =============================================================================