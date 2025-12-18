# =============================================================================
# Multi-stage Dockerfile for TimescaleDB + CloudNativePG (Bookworm base)
# Builds and assembles pgvector (C), pgvectorscale (Rust), and TimescaleDB
# extensions for PostgreSQL with AI/vector workload support on Kubernetes.
# TimescaleDB version is determined by the apt package manager (Stage 3).
# =============================================================================

ARG PG_MAJOR=17
ARG PGVECTOR_VERSION=0.8.1
ARG PGVECTORSCALE_VERSION=0.9.0
ARG RUST_VERSION=1.91
ARG PGRX_VERSION=0.16.1

# STAGE 1: Build pgvector (C extension)
# Compiles pgvector from source to produce .so and .sql artifacts.
# Uses shallow clone (--depth 1) to minimize build layer size.
FROM ghcr.io/cloudnative-pg/postgresql:${PG_MAJOR}-bookworm AS pgvector-builder

ARG PG_MAJOR
ARG PGVECTOR_VERSION

USER root

# Add PGDG repo for PostgreSQL build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
   ca-certificates gnupg lsb-release curl && rm -rf /var/lib/apt/lists/*

RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
   curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Install build tools and PostgreSQL development headers for the target version
RUN apt-get update && apt-get install -y --no-install-recommends \
   build-essential git postgresql-server-dev-${PG_MAJOR} \
   && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git

WORKDIR /tmp/pgvector
# Build with OPTFLAGS="" to ensure consistent compilation across architectures
RUN make clean && make OPTFLAGS="" && make install

# STAGE 2: Build pgvectorscale (Rust extension)
# Compiles pgvectorscale using cargo-pgrx to produce .so and .sql artifacts.
# Rust-based extension for disk-based vector indexing with improved performance.
FROM rust:${RUST_VERSION}-bookworm AS pgvectorscale-builder

ARG PG_MAJOR
ARG PGVECTORSCALE_VERSION
ARG PGRX_VERSION

USER root

# Add PGDG repo for PostgreSQL build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
   ca-certificates gnupg lsb-release curl && rm -rf /var/lib/apt/lists/*

RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
   curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Install build tools, PostgreSQL dev headers, and dependencies for Rust compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
   build-essential git postgresql-server-dev-${PG_MAJOR} \
   postgresql-${PG_MAJOR} clang pkg-config libssl-dev \
   && rm -rf /var/lib/apt/lists/*

# Install cargo-pgrx: Rust framework for PostgreSQL extension development
RUN cargo install --locked cargo-pgrx --version ${PGRX_VERSION}
# Initialize pgrx with the target PostgreSQL version
RUN cargo pgrx init --pg${PG_MAJOR} /usr/bin/pg_config

WORKDIR /tmp
RUN git clone --branch ${PGVECTORSCALE_VERSION} --depth 1 https://github.com/timescale/pgvectorscale.git

WORKDIR /tmp/pgvectorscale/pgvectorscale
# Enable SIMD optimizations (AVX2, FMA) for vectorized operations on x86-64 v3+
ENV RUSTFLAGS="-C target-cpu=x86-64-v3 -C target-feature=+avx2,+fma"
RUN cargo pgrx install --pg-config /usr/bin/pg_config

# STAGE 3: Install TimescaleDB (Bookworm)
# Installs TimescaleDB extension via apt package manager.
# TimescaleDB version is determined by the latest available in the apt repository.
FROM ghcr.io/cloudnative-pg/postgresql:${PG_MAJOR}-bookworm AS timescaledb-builder

ARG PG_MAJOR

USER root

# Add Timescale package repository
RUN apt-get update && apt-get install -y --no-install-recommends \
   ca-certificates gnupg lsb-release curl && rm -rf /var/lib/apt/lists/*

RUN echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/timescaledb.list && \
   curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg

# Add PGDG repository for PostgreSQL dependencies
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
   curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# Install TimescaleDB extension package for the target PostgreSQL version
RUN apt-get update && apt-get install -y --no-install-recommends \
   timescaledb-2-postgresql-${PG_MAJOR} \
   && rm -rf /var/lib/apt/lists/*

# STAGE 4: Final image + assembly
# Combines all extension artifacts from builder stages into a single, lean image.
# Only extension binaries and metadata are copied; build dependencies are discarded.
FROM ghcr.io/cloudnative-pg/postgresql:${PG_MAJOR}-bookworm

ARG PG_MAJOR

USER root

# Copy pgvector extension artifacts (C extension)
# Includes compiled .so library and SQL migration files
COPY --from=pgvector-builder \
   /usr/lib/postgresql/${PG_MAJOR}/lib/vector.so \
   /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=pgvector-builder \
   /usr/share/postgresql/${PG_MAJOR}/extension/vector*.sql \
   /usr/share/postgresql/${PG_MAJOR}/extension/
COPY --from=pgvector-builder \
   /usr/share/postgresql/${PG_MAJOR}/extension/vector.control \
   /usr/share/postgresql/${PG_MAJOR}/extension/

# Copy pgvectorscale extension artifacts (Rust extension)
# Includes compiled .so library and SQL migration files
COPY --from=pgvectorscale-builder \
   /usr/lib/postgresql/${PG_MAJOR}/lib/vectorscale-*.so \
   /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=pgvectorscale-builder \
   /usr/share/postgresql/${PG_MAJOR}/extension/vectorscale*.sql \
   /usr/share/postgresql/${PG_MAJOR}/extension/
COPY --from=pgvectorscale-builder \
   /usr/share/postgresql/${PG_MAJOR}/extension/vectorscale.control \
   /usr/share/postgresql/${PG_MAJOR}/extension/

# Copy TimescaleDB extension artifacts
# Includes compiled .so library and SQL migration files
COPY --from=timescaledb-builder \
   /usr/lib/postgresql/${PG_MAJOR}/lib/timescaledb*.so \
   /usr/lib/postgresql/${PG_MAJOR}/lib/
COPY --from=timescaledb-builder \
   /usr/share/postgresql/${PG_MAJOR}/extension/timescaledb*.sql \
   /usr/share/postgresql/${PG_MAJOR}/extension/
COPY --from=timescaledb-builder \
   /usr/share/postgresql/${PG_MAJOR}/extension/timescaledb.control \
   /usr/share/postgresql/${PG_MAJOR}/extension/

# Switch to CloudNativePG's unprivileged user (UID 26)
USER 26

LABEL org.opencontainers.image.title="CloudNativePG TimescaleDB + pgvector + pgvectorscale (Bookworm)"
LABEL org.opencontainers.image.description="PostgreSQL ${PG_MAJOR} with TimescaleDB, pgvector, and pgvectorscale for AI workloads on Kubernetes"
LABEL org.opencontainers.image.source="https://github.com/your-org/your-repo"
