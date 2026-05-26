CREATE EXTENSION IF NOT EXISTS hstore;
CREATE SCHEMA IF NOT EXISTS ext_lang;

DO $$
BEGIN
    PERFORM 1 FROM pg_type WHERE typname = 'lang';
    IF NOT FOUND THEN
        CREATE DOMAIN lang AS hstore;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS ext_lang.languages (
    code text PRIMARY KEY,
    is_active boolean NOT NULL DEFAULT true,
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ext_lang_languages_code_chk CHECK (code ~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$')
);

CREATE UNIQUE INDEX IF NOT EXISTS ext_lang_languages_one_default_idx
    ON ext_lang.languages (is_default)
    WHERE is_default;

INSERT INTO ext_lang.languages (code, is_active, is_default)
VALUES ('en_US', true, true)
ON CONFLICT (code) DO NOTHING;

CREATE OR REPLACE FUNCTION ext_lang._lang_validate_lang(p_lang text)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_lang text;
BEGIN
    v_lang := NULLIF(trim(p_lang), '');
    IF v_lang IS NULL THEN
        RAISE EXCEPTION 'Language code is empty';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM ext_lang.languages l
        WHERE l.code = v_lang
          AND l.is_active
    ) THEN
        RAISE EXCEPTION 'Unknown or inactive language: %', v_lang;
    END IF;

    RETURN v_lang;
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_default_lang()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT l.code
    FROM ext_lang.languages l
    WHERE l.is_default
    LIMIT 1
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_get_lang()
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_lang text;
BEGIN
    v_lang := NULLIF(current_setting('ext_lang.current', true), '');
    IF v_lang IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN ext_lang._lang_validate_lang(v_lang);
EXCEPTION
    WHEN others THEN
        RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_set_lang(p_lang text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_lang text;
BEGIN
    v_lang := ext_lang._lang_validate_lang(p_lang);
    PERFORM set_config('ext_lang.current', v_lang, false);
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_to_hstore(p_value lang)
RETURNS hstore
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(p_value::hstore, ''::hstore)
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_src(p_value lang)
RETURNS hstore
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ext_lang._lang_to_hstore(p_value)
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_s(p_value lang, p_lang text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_store hstore;
    v_lang text;
    v_default text;
    v_value text;
BEGIN
    IF p_value IS NULL THEN
        RETURN NULL;
    END IF;

    v_store := ext_lang._lang_to_hstore(p_value);
    v_lang := COALESCE(NULLIF(trim(p_lang), ''), ext_lang._lang_get_lang());

    IF v_lang IS NOT NULL THEN
        v_lang := ext_lang._lang_validate_lang(v_lang);
        v_value := v_store -> v_lang;
        IF v_value IS NOT NULL THEN
            RETURN v_value;
        END IF;
    END IF;

    v_default := ext_lang._lang_default_lang();
    IF v_default IS NOT NULL THEN
        v_value := v_store -> v_default;
        IF v_value IS NOT NULL THEN
            RETURN v_value;
        END IF;
    END IF;

    RETURN v_store -> '__default';
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_u(p_value lang, p_new_value text)
RETURNS lang
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_store hstore;
    v_lang text;
    v_default text;
BEGIN
    v_lang := ext_lang._lang_get_lang();
    IF v_lang IS NULL THEN
        RAISE EXCEPTION 'ext_lang.current is not set';
    END IF;

    v_store := ext_lang._lang_to_hstore(p_value);
    v_store := v_store || hstore(v_lang, p_new_value);

    v_default := ext_lang._lang_default_lang();
    IF (v_store -> '__default') IS NULL THEN
        IF v_default = v_lang THEN
            v_store := v_store || hstore('__default', p_new_value);
        ELSIF (v_store -> v_default) IS NOT NULL THEN
            v_store := v_store || hstore('__default', v_store -> v_default);
        END IF;
    END IF;

    RETURN v_store::lang;
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_insert(p_new_value text)
RETURNS lang
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN ext_lang._lang_u(NULL::lang, p_new_value);
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_add_language(p_code text, p_is_default boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_code text;
BEGIN
    v_code := NULLIF(trim(p_code), '');
    IF v_code IS NULL THEN
        RAISE EXCEPTION 'Language code is empty';
    END IF;

    INSERT INTO ext_lang.languages (code, is_active, is_default)
    VALUES (v_code, true, p_is_default)
    ON CONFLICT (code) DO UPDATE
    SET is_active = EXCLUDED.is_active,
        is_default = CASE WHEN EXCLUDED.is_default THEN true ELSE ext_lang.languages.is_default END;

    IF p_is_default THEN
        UPDATE ext_lang.languages
        SET is_default = false
        WHERE code <> v_code
          AND is_default;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_backfill_value(
    p_value lang,
    p_lang text,
    p_fill_mode text DEFAULT 'empty'
)
RETURNS lang
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_store hstore;
    v_lang text;
    v_mode text;
    v_fill text;
BEGIN
    v_lang := ext_lang._lang_validate_lang(p_lang);
    v_mode := lower(COALESCE(NULLIF(trim(p_fill_mode), ''), 'empty'));

    IF v_mode NOT IN ('empty', 'default') THEN
        RAISE EXCEPTION 'Unsupported fill mode: %', v_mode;
    END IF;

    v_store := ext_lang._lang_to_hstore(p_value);
    IF v_store ? v_lang THEN
        RETURN v_store::lang;
    END IF;

    IF v_mode = 'default' THEN
        v_fill := COALESCE(v_store -> '__default', '');
    ELSE
        v_fill := '';
    END IF;

    v_store := v_store || hstore(v_lang, v_fill);
    RETURN v_store::lang;
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_has_key(p_value lang, p_lang text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ext_lang._lang_to_hstore(p_value) ? p_lang
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_backfill_language(
    p_table regclass,
    p_column text,
    p_lang text,
    p_fill_mode text DEFAULT 'empty'
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql text;
    v_rows bigint;
BEGIN
    PERFORM ext_lang._lang_validate_lang(p_lang);

    v_sql := format(
        'UPDATE %s SET %I = ext_lang._lang_backfill_value(%I, %L, %L) WHERE NOT ext_lang._lang_has_key(%I, %L)',
        p_table,
        p_column,
        p_column,
        p_lang,
        p_fill_mode,
        p_column,
        p_lang
    );

    EXECUTE v_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION ext_lang._lang_backfill_language_all(
    p_lang text,
    p_fill_mode text DEFAULT 'empty'
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    v_total bigint := 0;
BEGIN
    FOR r IN
        SELECT
            c.oid::regclass AS table_name,
            a.attname AS column_name
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_type t ON t.oid = a.atttypid
        WHERE c.relkind = 'r'
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND t.typname = 'lang'
          AND n.nspname NOT IN ('pg_catalog', 'information_schema')
    LOOP
        v_total := v_total + ext_lang._lang_backfill_language(r.table_name, r.column_name, p_lang, p_fill_mode);
    END LOOP;

    RETURN v_total;
END;
$$;
