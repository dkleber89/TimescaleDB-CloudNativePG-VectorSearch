-- =============================================================================
-- Stock Pattern Recognition System - Schema Definition
-- =============================================================================
-- Creates the foundation for time-series stock data with vector embeddings
-- for pattern similarity searches. Uses TimescaleDB hypertables for efficient
-- time-series storage and pgvector for vector operations.
--
-- Prerequisites: 
--   - timescaledb extension enabled
--   - vector extension enabled
--   - vectorscale extension enabled
-- =============================================================================

-- Stock price time-series table (OHLCV data)
-- Stores minute-level price data for 10 stocks over 30 days
CREATE TABLE IF NOT EXISTS stock_prices (
    time        TIMESTAMPTZ NOT NULL,
    symbol      TEXT NOT NULL,
    open        NUMERIC(10,2) NOT NULL,
    high        NUMERIC(10,2) NOT NULL,
    low         NUMERIC(10,2) NOT NULL,
    close       NUMERIC(10,2) NOT NULL,
    volume      BIGINT NOT NULL,
    
    -- Constraints ensure data integrity
    CONSTRAINT stock_prices_pkey PRIMARY KEY (time, symbol),
    CONSTRAINT positive_prices CHECK (open > 0 AND high > 0 AND low > 0 AND close > 0),
    CONSTRAINT high_low_check CHECK (high >= low),
    CONSTRAINT positive_volume CHECK (volume >= 0)
);

-- Convert to TimescaleDB hypertable - enables automatic time-based partitioning
-- Chunks data by time for efficient querying and compression
SELECT create_hypertable('stock_prices', 'time', if_not_exists => TRUE);

-- Index for fast symbol-based lookups with time ordering
CREATE INDEX IF NOT EXISTS idx_stock_prices_symbol ON stock_prices (symbol, time DESC);

-- =============================================================================

-- Pattern embeddings table
-- Each row represents a stock's price movement pattern over a 24-hour window
-- Embeddings are 384-dimensional vectors capturing price dynamics
CREATE TABLE IF NOT EXISTS pattern_embeddings (
    id          SERIAL,
    time        TIMESTAMPTZ NOT NULL,
    symbol      TEXT NOT NULL,
    
    -- Vector embedding (384 dimensions - typical for sentence transformers)
    -- Represents normalized price movements over 24-hour window
    embedding   vector(384) NOT NULL,
    
    -- Metadata about the pattern for filtering and analysis
    window_hours    INTEGER NOT NULL DEFAULT 24,
    volatility      NUMERIC(8,4),  -- Standard deviation of returns
    trend           NUMERIC(8,4),  -- Overall trend (positive/negative)
    
    -- Constraints - time in PRIMARY KEY for hypertable compatibility
    CONSTRAINT pattern_embeddings_pkey PRIMARY KEY (time, id),
    CONSTRAINT unique_pattern_per_time UNIQUE (time, symbol, window_hours)
);

-- Convert to hypertable for time-based partitioning and compression
SELECT create_hypertable('pattern_embeddings', 'time', if_not_exists => TRUE);

-- Index for fast symbol + time range queries (used by sample queries)
CREATE INDEX IF NOT EXISTS idx_pattern_embeddings_symbol_time 
    ON pattern_embeddings (symbol, time DESC);

-- =============================================================================

-- Convenience view for recent patterns (last 7 days)
-- Joins embeddings with current prices for quick analysis
CREATE OR REPLACE VIEW recent_patterns AS
SELECT 
    pe.time,
    pe.symbol,
    pe.embedding,
    pe.volatility,
    pe.trend,
    sp.close as current_price
FROM pattern_embeddings pe
JOIN stock_prices sp ON pe.symbol = sp.symbol AND pe.time = sp.time
WHERE pe.time > NOW() - INTERVAL '7 days'
ORDER BY pe.time DESC;

-- =============================================================================
-- Schema Summary
-- =============================================================================
-- Tables created:
--   1. stock_prices: Time-series OHLCV data (hypertable)
--      - Stores minute-level price data
--      - Partitioned by time for efficient storage and queries
--   2. pattern_embeddings: Vector embeddings of price patterns (hypertable)
--      - 384-dimensional vectors representing price movements
--      - Includes volatility and trend metadata
--
-- Next step: Run seed-data.sql to populate stock_prices
-- =============================================================================