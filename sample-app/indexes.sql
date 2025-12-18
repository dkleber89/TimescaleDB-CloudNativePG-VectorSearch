-- =============================================================================
-- Stock Pattern Recognition System - Create Vector Indexes
-- =============================================================================
-- Creates StreamingDiskANN indexes (pgvectorscale) for fast similarity searches.
-- DiskANN enables efficient approximate nearest neighbor search on disk.
-- 
-- Index Strategy:
--   - Use diskann (pgvectorscale) for large-scale vector search
--   - Configure for disk-based operation (suitable for K3s/edge deployments)
--   - Optimize for cosine similarity (most common in pattern matching)
--   - Includes L2 distance as alternative metric
-- =============================================================================

-- Drop existing indexes if rebuilding
DROP INDEX IF EXISTS idx_pattern_embeddings_diskann_cosine;
DROP INDEX IF EXISTS idx_pattern_embeddings_diskann_l2;

-- =============================================================================
-- Create StreamingDiskANN index for cosine similarity (PRIMARY)
-- =============================================================================
-- This is the primary index for finding stocks with similar price patterns
-- Cosine similarity is preferred for pattern matching as it's scale-invariant
-- (normalized vectors have consistent distances regardless of magnitude)

CREATE INDEX idx_pattern_embeddings_diskann_cosine 
    ON pattern_embeddings 
    USING diskann (embedding vector_cosine_ops)
    WITH (
        num_neighbors = 50,           -- Graph connectivity (higher = better recall, more memory)
        search_list_size = 100,       -- Search quality (higher = more accurate, slower queries)
        max_alpha = 1.2,              -- Graph pruning aggressiveness (1.0-1.5 range)
        num_dimensions = 384,         -- Vector dimensionality (must match embedding size)
        num_bits_per_dimension = 2    -- Quantization level (2 bits = 4 levels, ~75% compression)
    );

-- =============================================================================
-- Create StreamingDiskANN index for L2 distance (Euclidean) (ALTERNATIVE)
-- =============================================================================
-- Alternative distance metric - useful for absolute magnitude comparisons
-- L2 distance considers both direction and magnitude of vectors

CREATE INDEX idx_pattern_embeddings_diskann_l2 
    ON pattern_embeddings 
    USING diskann (embedding vector_l2_ops)
    WITH (
        num_neighbors = 50,
        search_list_size = 100,
        max_alpha = 1.2,
        num_dimensions = 384,
        num_bits_per_dimension = 2
    );

-- =============================================================================
-- Verify index creation and show statistics
-- =============================================================================

DO $$
DECLARE
    index_info RECORD;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Vector Indexes Created';
    RAISE NOTICE '========================================';
    
    FOR index_info IN 
        SELECT 
            indexname,
            pg_size_pretty(pg_relation_size(indexname::regclass)) as index_size
        FROM pg_indexes 
        WHERE tablename = 'pattern_embeddings' 
          AND indexname LIKE '%diskann%'
        ORDER BY indexname
    LOOP
        RAISE NOTICE 'Index: %', index_info.indexname;
        RAISE NOTICE '  Size: %', index_info.index_size;
    END LOOP;
    
    RAISE NOTICE '========================================';
END $$;

-- Show index usage statistics - tracks index performance
SELECT 
    schemaname,
    indexrelname as index_name,
    relname as table_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE relname = 'pattern_embeddings'
ORDER BY indexrelname;

-- =============================================================================
-- Index Configuration Notes
-- =============================================================================
-- 
-- Parameter Tuning Guide:
-- 
-- num_neighbors (default: -1 = auto):
--   - Controls graph connectivity
--   - Higher values: Better recall, more memory, slower builds
--   - Recommended: 30-100 for most workloads
--
-- search_list_size (default: 100):
--   - Candidate list size during search
--   - Higher values: More accurate, slower queries
--   - Recommended: 100-200 for production
--
-- max_alpha (default: 1.2):
--   - Graph pruning parameter
--   - Lower values: Smaller index, potentially lower recall
--   - Range: 1.0-1.5
--
-- num_bits_per_dimension (default: 2):
--   - Quantization level for compression
--   - 1 bit = 50% compression, 2 bits = 75% compression
--   - Trade-off: Size vs accuracy
--
-- storage_layout (default: SbqCompression):
--   - Automatic scalar quantization for space savings
--   - No configuration needed
--
-- =============================================================================
-- Next: Run sample queries (sample-queries.sql)
-- =============================================================================