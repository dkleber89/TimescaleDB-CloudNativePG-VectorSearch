# TimescaleDB + pgvectorscale for AI on Kubernetes

## � Getting Started

Before deploying to Kubernetes, you need to configure one placeholder in the image catalog:

### Required Configuration: Container Image Reference

**File:** `kubernetes/imagecatalog-timescaledb.yaml` (line 23)

This file references your custom PostgreSQL image with TimescaleDB, pgvector, and pgvectorscale extensions. You must replace the placeholder with your actual container registry details.

**Replace this:**
```yaml
image: REGISTRY/IMAGE_NAME:IMAGE_TAG
```

**With one of these examples:**
```yaml
# Docker Hub
image: docker.io/myusername/IMAGE_NAME:IMAGE_TAG

# GitHub Container Registry
image: ghcr.io/myusername/IMAGE_NAME:IMAGE_TAG
```

---

## 🎯 Running Tests: Interactive Test Orchestrator

**File:** `run-capability-tests.sh`

This is your entry point for all capability testing. The script provides an interactive menu to validate and demonstrate the stack.

**What it does:**

1. **Prerequisites Check:**
   - Verifies kubectl, cluster, pod status, and database initialization

2. **Mode 1 - Quick Validation (~2 min):**
   - Runs 3 tests on existing 1.8K vectors
   - Validates all extensions are working
   - Confirms indexes and basic operations

3. **Mode 2 - Full Capability Demo (~15 min):**
   - Generates 50K vectors over 9 months
   - Runs 3 advanced tests demonstrating production-scale capabilities
   - Shows time-windowed queries, compression, and vector search at scale

4. **Interactive Loop:**
   - Returns to menu after each test run
   - Allows multiple test runs without restarting script

---

## 📊 Test Files Reference

The `sample-app/tests/` directory contains the SQL scripts that `run-capability-tests.sh` orchestrates. You don't need to run these manually—the script handles everything. This section explains what each test does.

### Quick Validation Tests (1.8K vectors)

These tests verify all extensions are working correctly:

| File | Location | Purpose |
|------|----------|---------|
| `test-vector-ops.sql` | `sample-app/tests/` | Validates **pgvector** extension: distance operators, similarity searches, vector dimensions |
| `test-diskann.sql` | `sample-app/tests/` | Validates **pgvectorscale** extension: DiskANN index creation, index usage in queries, statistics |
| `test-timescaledb-basic.sql` | `sample-app/tests/` | Validates **TimescaleDB**: hypertables, chunks, time-based queries, basic compression |

### Full Capability Demo Tests (50K vectors)

These tests demonstrate production-scale performance and features:

| File | Location | Purpose |
|------|----------|---------|
| `generate-large-dataset.sql` | `sample-app/tests/` | Generates 50,000 synthetic vectors distributed over 9 months for scale testing |
| `test-time-windows-advanced.sql` | `sample-app/tests/` | Demonstrates **time-windowed query efficiency**: chunk exclusion, performance with time filters vs full scans |
| `test-compression-scale.sql` | `sample-app/tests/` | Demonstrates **TimescaleDB compression**: space savings (60-70%), transparent queries on compressed data |
| `test-vector-scale.sql` | `sample-app/tests/` | Demonstrates **vector search at scale**: similarity queries on 50K vectors, index usage statistics, sub-linear scaling |
