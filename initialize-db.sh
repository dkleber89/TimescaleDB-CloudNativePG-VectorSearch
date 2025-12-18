#!/bin/bash
# =============================================================================
# Database Initialization Script
# =============================================================================
# Sets up the sample application database with:
#   - Schema (hypertables for stock prices and embeddings)
#   - Sample data (432K stock price records)
#   - Vector embeddings (1,800 pattern embeddings)
#   - Indexes (including DiskANN vector indexes)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="timescaledb"
POD="timescaledb-cluster-1"

# =============================================================================
# Helper Functions
# =============================================================================

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}📊 $1${NC}"
}

# =============================================================================
# Main Initialization
# =============================================================================

print_info "Initializing database..."
echo ""

# Execute all SQL files in order
for file in schema seed-data create-embeddings indexes; do
    echo "Running $file.sql..."
    kubectl exec -i $POD -n $NAMESPACE -- \
        psql -U postgres -d app < sample-app/$file.sql
    echo ""
done

# =============================================================================
# Gather Verification Data
# =============================================================================

print_info "Gathering verification data..."

# Get extension info
EXTENSIONS=$(kubectl exec -i $POD -n $NAMESPACE -- \
    psql -U postgres -d app -tAc "
SELECT string_agg(extname || ' ' || extversion, ', ' ORDER BY extname)
FROM pg_extension 
WHERE extname IN ('timescaledb', 'vector', 'vectorscale');")

# Get data counts
DATA_STATS=$(kubectl exec -i $POD -n $NAMESPACE -- \
    psql -U postgres -d app -tAc "
SELECT 
    (SELECT COUNT(*) FROM stock_prices)::TEXT || '|' ||
    (SELECT COUNT(DISTINCT symbol) FROM stock_prices)::TEXT || '|' ||
    (SELECT COUNT(*) FROM pattern_embeddings)::TEXT || '|' ||
    (SELECT COUNT(DISTINCT symbol) FROM pattern_embeddings)::TEXT;")

# Parse data stats
IFS='|' read -r STOCK_ROWS STOCK_SYMBOLS EMBEDDING_ROWS EMBEDDING_SYMBOLS <<< "$DATA_STATS"

# Get index count
INDEX_COUNT=$(kubectl exec -i $POD -n $NAMESPACE -- \
    psql -U postgres -d app -tAc "
SELECT COUNT(*) FROM pg_indexes 
WHERE tablename IN ('stock_prices', 'pattern_embeddings');")

# Get DiskANN index count
DISKANN_COUNT=$(kubectl exec -i $POD -n $NAMESPACE -- \
    psql -U postgres -d app -tAc "
SELECT COUNT(*) FROM pg_indexes 
WHERE tablename = 'pattern_embeddings' AND indexname LIKE '%diskann%';")

# =============================================================================
# Display Detailed Verification
# =============================================================================

echo ""
echo "📈 Detailed Verification:"
echo "-------------------------"

# Show extensions
kubectl exec -it $POD -n $NAMESPACE -- \
    psql -U postgres -d app -c "
SELECT extname, extversion 
FROM pg_extension 
WHERE extname IN ('timescaledb', 'vector', 'vectorscale')
ORDER BY extname;"

echo ""

# Show data counts
kubectl exec -it $POD -n $NAMESPACE -- \
    psql -U postgres -d app -c "
SELECT 
    'Stock prices' as table,
    COUNT(*) as rows,
    COUNT(DISTINCT symbol) as symbols
FROM stock_prices
UNION ALL
SELECT 
    'Embeddings',
    COUNT(*),
    COUNT(DISTINCT symbol)
FROM pattern_embeddings;"

# =============================================================================
# Success Summary
# =============================================================================

echo ""
echo "=========================================="
print_success "Database Initialization Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  • Extensions: $EXTENSIONS"
echo "  • Stock data: $(printf "%'d" $STOCK_ROWS) rows ($STOCK_SYMBOLS stocks)"
echo "  • Embeddings: $(printf "%'d" $EMBEDDING_ROWS) vectors ($EMBEDDING_SYMBOLS stocks)"
echo "  • Indexes: $INDEX_COUNT total ($DISKANN_COUNT DiskANN)"
echo ""
echo "Next Steps:"
echo "  Run: ./run-capability-tests.sh"
echo ""