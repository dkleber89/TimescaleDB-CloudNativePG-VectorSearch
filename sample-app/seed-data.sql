-- =============================================================================
-- Stock Pattern Recognition System - Sample Data Generation
-- =============================================================================
-- Generates realistic sample data for demonstration and testing:
--   - 10 popular tech stocks (AAPL, TSLA, NVDA, etc.)
--   - 30 days of minute-level price data (realistic market data)
--   - ~432,000 total rows (10 stocks × 1440 minutes/day × 30 days)
-- Uses realistic price movements with trend, seasonality, and volatility
-- =============================================================================

-- Generate stock price data with realistic patterns
WITH 
-- Define stock universe with realistic base prices
stocks AS (
    SELECT symbol, base_price FROM (VALUES
        ('AAPL', 180.00),
        ('TSLA', 250.00),
        ('NVDA', 450.00),
        ('MSFT', 380.00),
        ('GOOGL', 140.00),
        ('AMZN', 175.00),
        ('META', 480.00),
        ('AMD', 140.00),
        ('INTC', 45.00),
        ('NFLX', 480.00)
    ) AS t(symbol, base_price)
),
-- Generate time series at minute-level granularity (last 30 days)
time_series AS (
    SELECT 
        generate_series(
            NOW() - INTERVAL '30 days',
            NOW(),
            INTERVAL '1 minute'
        ) AS time
),
-- Combine each stock with each time point
stock_timeline AS (
    SELECT 
        ts.time,
        s.symbol,
        s.base_price
    FROM time_series ts
    CROSS JOIN stocks s
),
-- Generate realistic price movements using random walk model
price_data AS (
    SELECT
        time,
        symbol,
        base_price,
        -- Random walk with trend and volatility components
        base_price * (
            1 + 
            -- Overall trend (slight upward bias - 0.01% per hour)
            0.0001 * EXTRACT(EPOCH FROM (time - (NOW() - INTERVAL '30 days')))::NUMERIC / 3600 +
            -- Daily seasonality (higher prices during market hours)
            0.002 * SIN(EXTRACT(HOUR FROM time) * PI() / 12) +
            -- Random noise (volatility - ±0.5%)
            (random() - 0.5) * 0.01
        ) AS price
    FROM stock_timeline
)
INSERT INTO stock_prices (time, symbol, open, high, low, close, volume)
SELECT
    time,
    symbol,
    price AS open,
    price * (1 + random() * 0.005) AS high,  -- High within 0.5% above open
    price * (1 - random() * 0.005) AS low,   -- Low within 0.5% below open
    price * (1 + (random() - 0.5) * 0.003) AS close,  -- Close near open (±0.15%)
    (1000000 + random() * 5000000)::BIGINT AS volume  -- Random volume (1M-6M shares)
FROM price_data
ON CONFLICT (time, symbol) DO NOTHING;

-- =============================================================================
-- Verify data insertion and show statistics
-- =============================================================================

DO $$
DECLARE
    row_count INTEGER;
    stock_count INTEGER;
    date_range TEXT;
BEGIN
    SELECT COUNT(*) INTO row_count FROM stock_prices;
    SELECT COUNT(DISTINCT symbol) INTO stock_count FROM stock_prices;
    SELECT 
        TO_CHAR(MIN(time), 'YYYY-MM-DD HH24:MI') || ' to ' || 
        TO_CHAR(MAX(time), 'YYYY-MM-DD HH24:MI')
    INTO date_range FROM stock_prices;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Sample Data Generation Complete';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total rows inserted: %', row_count;
    RAISE NOTICE 'Number of stocks: %', stock_count;
    RAISE NOTICE 'Date range: %', date_range;
    RAISE NOTICE '========================================';
END $$;

-- Show data distribution by stock - validates data quality
SELECT 
    symbol,
    COUNT(*) as data_points,
    MIN(time) as first_timestamp,
    MAX(time) as last_timestamp,
    ROUND(AVG(close), 2) as avg_price,
    ROUND(MIN(low), 2) as min_price,
    ROUND(MAX(high), 2) as max_price
FROM stock_prices
GROUP BY symbol
ORDER BY symbol;
