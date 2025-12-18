-- =============================================================================
-- Stock Pattern Recognition System - Generate Pattern Embeddings
-- =============================================================================
-- Creates 384-dimensional vector embeddings representing 24-hour price patterns
-- Each embedding captures:
--   - Normalized returns over time windows
--   - Volatility characteristics
--   - Momentum indicators
--
-- Note: In production, embeddings would come from ML models (LSTM, Transformers).
-- Here we simulate embeddings using statistical features for demonstration.
-- This approach is suitable for testing the vector search infrastructure.
-- =============================================================================

-- Generate embeddings for 24-hour windows, sampled every 4 hours
WITH 
-- Define time windows (every 4 hours over last 30 days)
time_windows AS (
    SELECT 
        generate_series(
            NOW() - INTERVAL '30 days',
            NOW(),
            INTERVAL '4 hours'
        ) AS window_end
),
-- Calculate 24-hour returns for each stock/window combination
price_returns AS (
    SELECT 
        tw.window_end,
        sp.symbol,
        sp.time,
        sp.close,
        LAG(sp.close) OVER (PARTITION BY sp.symbol ORDER BY sp.time) as prev_close
    FROM time_windows tw
    CROSS JOIN (SELECT DISTINCT symbol FROM stock_prices) AS symbols
    JOIN stock_prices sp 
        ON sp.symbol = symbols.symbol
        AND sp.time >= tw.window_end - INTERVAL '24 hours' 
        AND sp.time <= tw.window_end
),
-- Aggregate returns and calculate statistics for pattern features
stock_patterns AS (
    SELECT 
        window_end AS time,
        symbol,
        -- Array of returns (current close / previous close - 1)
        ARRAY_AGG(
            CASE 
                WHEN prev_close IS NOT NULL AND prev_close > 0 
                THEN (close - prev_close) / prev_close 
                ELSE 0 
            END 
            ORDER BY time
        ) AS returns,
        -- Volatility (std dev of prices) - measure of price variability
        STDDEV(close) AS volatility,
        -- Trend (linear regression slope) - direction of price movement
        REGR_SLOPE(close, EXTRACT(EPOCH FROM time)) AS trend,
        COUNT(*) as data_points
    FROM price_returns
    GROUP BY window_end, symbol
    HAVING COUNT(*) >= 100  -- Ensure sufficient data points for reliable statistics
),
-- Generate synthetic embeddings (384 dimensions)
-- In production: use actual ML model embeddings from LSTM or Transformers
synthetic_embeddings AS (
    SELECT
        time,
        symbol,
        volatility,
        trend,
        returns,
        data_points,
        -- Create 384-dim vector from statistical features
        -- Dimensions 1-128: Normalized returns pattern (repeated/interpolated)
        -- Dimensions 129-256: Volatility-weighted returns
        -- Dimensions 257-384: Momentum and trend features
        (
            SELECT ARRAY_AGG(
                CASE 
                    WHEN i <= 128 THEN 
                        -- Returns pattern (normalized to 0-1 range)
                        COALESCE(
                            returns[LEAST(((i-1) * array_length(returns, 1) / 128) + 1, array_length(returns, 1))], 
                            0
                        )::NUMERIC * 100
                    WHEN i <= 256 THEN
                        -- Volatility-weighted returns (amplifies volatile patterns)
                        COALESCE(
                            returns[LEAST(((i-129) * array_length(returns, 1) / 128) + 1, array_length(returns, 1))],
                            0
                        )::NUMERIC * COALESCE(volatility, 1) * 10
                    ELSE
                        -- Momentum features (trend-based with sine wave modulation)
                        SIN((i - 256) * PI() / 128) * COALESCE(trend, 0) * 1000 +
                        (random() - 0.5) * 0.1  -- Small noise for realism
                END::FLOAT4
            )
            FROM generate_series(1, 384) AS i
        )::vector(384) AS embedding
    FROM stock_patterns
    WHERE returns IS NOT NULL 
      AND array_length(returns, 1) > 0
)
INSERT INTO pattern_embeddings (time, symbol, embedding, window_hours, volatility, trend)
SELECT 
    time,
    symbol,
    embedding,
    24 AS window_hours,
    ROUND(volatility::NUMERIC, 4),
    ROUND(trend::NUMERIC, 4)
FROM synthetic_embeddings
WHERE embedding IS NOT NULL
ON CONFLICT (time, symbol, window_hours) DO NOTHING;

-- =============================================================================
-- Verify embeddings generation and show statistics
-- =============================================================================

DO $$
DECLARE
    embedding_count INTEGER;
    stock_count INTEGER;
    avg_volatility NUMERIC;
BEGIN
    SELECT COUNT(*) INTO embedding_count FROM pattern_embeddings;
    SELECT COUNT(DISTINCT symbol) INTO stock_count FROM pattern_embeddings;
    SELECT ROUND(AVG(volatility), 4) INTO avg_volatility FROM pattern_embeddings;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Pattern Embeddings Generated';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total embeddings: %', embedding_count;
    RAISE NOTICE 'Stocks with embeddings: %', stock_count;
    RAISE NOTICE 'Average volatility: %', avg_volatility;
    RAISE NOTICE '========================================';
END $$;

-- Show embedding statistics per stock - validates embedding generation
SELECT 
    symbol,
    COUNT(*) as num_patterns,
    ROUND(AVG(volatility), 4) as avg_volatility,
    ROUND(AVG(trend), 6) as avg_trend,
    MIN(time) as earliest_pattern,
    MAX(time) as latest_pattern
FROM pattern_embeddings
GROUP BY symbol
ORDER BY symbol;

-- =============================================================================
-- Next: Create DiskANN indexes for fast similarity search (indexes.sql)
-- =============================================================================