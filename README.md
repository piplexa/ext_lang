# ext_lang

Русская версия: [README.ru.md](README.ru.md)

Citizens! Store your translations in the database! It's convenient and easy.

PostgreSQL extension for localized text storage with:
- transparent SELECT and INSERT for type ext_lang.lang;
- explicit UPDATE via a single function ext_lang.u(...);
- hstore-backed payload with language fallback.

## Repository Layout

- ext_lang/ - extension source (C + SQL + control)
- docker/ - image build for PostgreSQL with installed extension
- initdb_ext_lang/ - init scripts for the active implementation
- initdb/ - legacy SQL backup (kept for reference, not used by runtime)
- tests/ - smoke tests
- docs/ - technical documentation

## Requirements

- Docker + Docker Compose

## Quick Start

1. Build and start database from clean state:

```bash
docker compose down -v
docker compose up -d --build
```

2. Verify extension installation:

```bash
docker compose exec -T postgres psql -U postgres -d app -c "SELECT extname FROM pg_extension ORDER BY 1;"
```

Expected output includes ext_lang.

## Usage

### 1) Create table

```sql
CREATE TABLE article (
    id serial PRIMARY KEY,
    title ext_lang.lang,
    views integer NOT NULL DEFAULT 0
);
```

### 2) Configure languages and current session language

```sql
SELECT ext_lang.add_language('ru_RU', false);
SELECT ext_lang.set_lang('ru_RU');
```

### 3) Insert (transparent)

```sql
INSERT INTO article (title, views) VALUES ('привет', 10);
```

### 4) Select (transparent)

```sql
SELECT id, title, views FROM article;
```

### 5) Update non-language fields (no ext_lang overhead)

```sql
UPDATE article SET views = 11 WHERE id = 1;
```

### 6) Update language field (explicit merge function)

```sql
SELECT ext_lang.set_lang('en_US');
UPDATE article SET title = ext_lang.u(title, 'hello') WHERE id = 1;
```

## Function Reference

Public API (application-level):

- ext_lang.add_language(code text, is_default boolean default false)
  - Registers a new language or re-activates existing one.
  - If is_default=true, switches default language to this code.

- ext_lang.set_lang(lang text)
  - Sets session language (GUC ext_lang.current).

- ext_lang.get_lang()
  - Returns active session language or NULL.

- ext_lang.default_lang()
  - Returns current default language code.

- ext_lang.u(old_value ext_lang.lang, new_text text)
  - UPDATE helper for lang columns.
  - Updates translation only for the current session language.
  - Preserves other translations.

- ext_lang.from_text(value text)
  - Converts plain text to ext_lang.lang using current session language.

- ext_lang.to_text(value ext_lang.lang)
  - Converts ext_lang.lang to localized text.

- ext_lang.raw_hstore(value ext_lang.lang)
  - Returns raw hstore payload for debugging and checks.

Internal helpers (used by extension internals, usually not called directly):

- ext_lang._validate_lang(lang text)
  - Validates language exists and is active.

- ext_lang._from_input_text(value text)
  - Builds initial hstore payload from plain text.

- ext_lang._localize(store hstore, lang text default null)
  - Resolves localized text with fallback logic.

- ext_lang.merge_lang(old_value ext_lang.lang, new_value ext_lang.lang)
  - Merges updated translation into existing payload.

- ext_lang.raw_text(value ext_lang.lang)
  - Returns raw textual form of underlying hstore.

- ext_lang.from_hstore_text(value text)
  - Reconstructs ext_lang.lang from raw hstore text.

## Fallback Behavior

Read path fallback order:
1. current session language
2. default language
3. __default key
4. first available key in hstore

## Smoke Test

Run smoke test from repository root:

```bash
docker compose exec -T postgres psql -U postgres -d app < tests/smoke_test.sql
```

Expected final line:

```text
smoke_test_ok
```

## Notes

- Active init directory is initdb_ext_lang.
- Legacy backup in initdb is intentionally preserved and not loaded by container startup.
- The project does not depend on functions from initdb/02-ext-lang.sql.
