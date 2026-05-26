# Installation Guide

Русская версия: [INSTALL.ru.md](INSTALL.ru.md)

This document describes all supported ways to install the `ext_lang` PostgreSQL extension.

## Contents

- [Requirements](#requirements)
- [Option A: Docker (recommended for quick start)](#option-a-docker-recommended-for-quick-start)
- [Option B: Local build from source (without Docker)](#option-b-local-build-from-source-without-docker)
- [Option C: Multiple PostgreSQL versions on one host](#option-c-multiple-postgresql-versions-on-one-host)
- [Enable extension in database](#enable-extension-in-database)
- [Verify installation](#verify-installation)
- [Troubleshooting](#troubleshooting)

## Requirements

- PostgreSQL 16 (or another supported version, with matching dev headers)
- C toolchain (`gcc` or `clang`), `make`
- PostgreSQL server development package (`pg_config` must be available)
- `hstore` extension in target database (required by `ext_lang`)

Project uses PGXS build system:
- source module: [ext_lang/ext_lang.c](ext_lang/ext_lang.c)
- build file: [ext_lang/Makefile](ext_lang/Makefile)
- control file: [ext_lang/ext_lang.control](ext_lang/ext_lang.control)

## Option A: Docker (recommended for quick start)

The repository already contains Docker setup that compiles and installs extension into PostgreSQL image:
- [docker/postgres-ext/Dockerfile](docker/postgres-ext/Dockerfile)
- [docker-compose.yaml](docker-compose.yaml)

From repository root:

```bash
docker compose down -v
docker compose up -d --build
```

## Option B: Local build from source (without Docker)

### Debian/Ubuntu example (PostgreSQL 16)

```bash
sudo apt update
sudo apt install -y build-essential postgresql-server-dev-16
```

### Build and install

Run from repository root:

```bash
cd ext_lang
make
sudo make install
```

This installs:
- shared library into PostgreSQL libdir
- extension SQL/control files into PostgreSQL extension directory

## Option C: Multiple PostgreSQL versions on one host

If multiple PostgreSQL versions are installed, explicitly set `PG_CONFIG`.

Example for PostgreSQL 16:

```bash
cd ext_lang
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
sudo make install PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
```

Check selected toolchain:

```bash
/usr/lib/postgresql/16/bin/pg_config --version
/usr/lib/postgresql/16/bin/pg_config --pkglibdir
/usr/lib/postgresql/16/bin/pg_config --sharedir
```

## Enable extension in database

Connect to target database and run:

```sql
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS ext_lang;
```

## Verify installation

In `psql`:

```sql
\dx
```

Or query directly:

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('hstore', 'ext_lang')
ORDER BY extname;
```

Quick smoke check:

```sql
SELECT ext_lang.default_lang();
```

Expected: one row with default language (for fresh install usually `en_US`).

## Troubleshooting

1. `pg_config` not found
- Install PostgreSQL dev package.
- Ensure expected `pg_config` is in `PATH`, or pass explicit `PG_CONFIG=...`.

2. Build succeeds but `CREATE EXTENSION ext_lang` fails with “could not open extension control file”
- Most common reason: build/install used a different PostgreSQL version than server runtime.
- Rebuild using the same version via `PG_CONFIG`.

3. `permission denied` on `make install`
- Install step writes into PostgreSQL system directories and usually requires root:
  - `sudo make install`

4. `required extension "hstore" is not installed`
- Run:
  - `CREATE EXTENSION hstore;`
  - then `CREATE EXTENSION ext_lang;`

5. Package names differ on your distro
- On non-Debian systems, install equivalent PostgreSQL server development package and build tools.
