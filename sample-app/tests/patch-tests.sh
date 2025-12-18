#!/bin/bash
# Utility script to patch test files with correct TimescaleDB function calls
# Fixes references to chunk size functions that may vary across TimescaleDB versions

# Patch compression test - replace generic total_size with proper pg_relation_size call
sed -i 's/total_size/pg_relation_size((chunk_schema || '\''.'\'

' || chunk_name)::regclass)/g' sample-app/tests/test-compression-retention.sql

# Patch time-windows test - ensure pg_size_pretty wraps the correct function call
sed -i 's/pg_size_pretty(total_size)/pg_size_pretty(pg_relation_size((chunk_schema || '\''.'\'

' || chunk_name)::regclass))/g' sample-app/tests/test-time-windows.sql

echo "✅ Tests patched!"