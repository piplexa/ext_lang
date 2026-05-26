CREATE SCHEMA IF NOT EXISTS ext_lang;

CREATE TABLE ext_lang.languages (
    code text PRIMARY KEY,
    is_active boolean NOT NULL DEFAULT true,
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ext_lang_languages_code_chk CHECK (code ~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$')
);

CREATE UNIQUE INDEX ext_lang_languages_one_default_idx
    ON ext_lang.languages (is_default)
    WHERE is_default;

INSERT INTO ext_lang.languages (code, is_active, is_default)
VALUES ('en_US', true, true)
ON CONFLICT (code) DO NOTHING;

CREATE FUNCTION ext_lang.add_language(p_code text, p_is_default boolean DEFAULT false)
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
    SET is_active = true,
        is_default = CASE WHEN EXCLUDED.is_default THEN true ELSE ext_lang.languages.is_default END;

    IF p_is_default THEN
        UPDATE ext_lang.languages
        SET is_default = false
        WHERE code <> v_code
          AND is_default;
    END IF;
END;
$$;

CREATE FUNCTION ext_lang._validate_lang(p_lang text)
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

CREATE FUNCTION ext_lang.default_lang()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT l.code
    FROM ext_lang.languages l
    WHERE l.is_default
    LIMIT 1
$$;

CREATE FUNCTION ext_lang.get_lang()
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

    RETURN ext_lang._validate_lang(v_lang);
EXCEPTION
    WHEN others THEN
        RETURN NULL;
END;
$$;

CREATE FUNCTION ext_lang.set_lang(p_lang text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_lang text;
BEGIN
    v_lang := ext_lang._validate_lang(p_lang);
    PERFORM set_config('ext_lang.current', v_lang, false);
END;
$$;

CREATE FUNCTION ext_lang._from_input_text(p_value text)
RETURNS hstore
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_lang text;
    v_store hstore;
BEGIN
    v_lang := ext_lang.get_lang();
    IF v_lang IS NULL THEN
        RAISE EXCEPTION 'ext_lang.current is not set';
    END IF;

    v_store := hstore(v_lang, p_value);
    IF (v_store -> '__default') IS NULL THEN
        v_store := v_store || hstore('__default', p_value);
    END IF;

    RETURN v_store;
END;
$$;

CREATE FUNCTION ext_lang._localize(p_store hstore, p_lang text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_lang text;
    v_default text;
    v_value text;
BEGIN
    IF p_store IS NULL THEN
        RETURN NULL;
    END IF;

    v_lang := COALESCE(NULLIF(trim(p_lang), ''), ext_lang.get_lang());
    IF v_lang IS NOT NULL THEN
        v_lang := ext_lang._validate_lang(v_lang);
        v_value := p_store -> v_lang;
        IF v_value IS NOT NULL THEN
            RETURN v_value;
        END IF;
    END IF;

    v_default := ext_lang.default_lang();
    IF v_default IS NOT NULL THEN
        v_value := p_store -> v_default;
        IF v_value IS NOT NULL THEN
            RETURN v_value;
        END IF;
    END IF;

    v_value := p_store -> '__default';
    IF v_value IS NOT NULL THEN
        RETURN v_value;
    END IF;

    SELECT value INTO v_value
    FROM each(p_store)
    LIMIT 1;

    RETURN v_value;
END;
$$;

CREATE TYPE ext_lang.lang;

CREATE FUNCTION ext_lang.ext_lang_in(cstring)
RETURNS ext_lang.lang
AS 'MODULE_PATHNAME', 'ext_lang_in'
LANGUAGE C
IMMUTABLE
STRICT;

CREATE FUNCTION ext_lang.ext_lang_out(ext_lang.lang)
RETURNS cstring
AS 'MODULE_PATHNAME', 'ext_lang_out'
LANGUAGE C
IMMUTABLE
STRICT;

CREATE TYPE ext_lang.lang (
    INPUT = ext_lang.ext_lang_in,
    OUTPUT = ext_lang.ext_lang_out,
    INTERNALLENGTH = variable,
    STORAGE = extended,
    CATEGORY = 'S'
);

CREATE FUNCTION ext_lang.from_text(text)
RETURNS ext_lang.lang
AS 'MODULE_PATHNAME', 'ext_lang_from_text'
LANGUAGE C
STRICT;

CREATE FUNCTION ext_lang.to_text(ext_lang.lang)
RETURNS text
AS 'MODULE_PATHNAME', 'ext_lang_to_text'
LANGUAGE C
STRICT;

CREATE FUNCTION ext_lang.raw_text(ext_lang.lang)
RETURNS text
AS 'MODULE_PATHNAME', 'ext_lang_raw_text'
LANGUAGE C
IMMUTABLE
STRICT;

CREATE FUNCTION ext_lang.from_hstore_text(text)
RETURNS ext_lang.lang
AS 'MODULE_PATHNAME', 'ext_lang_from_hstore_text'
LANGUAGE C
IMMUTABLE
STRICT;

CREATE CAST (text AS ext_lang.lang)
WITH FUNCTION ext_lang.from_text(text)
AS IMPLICIT;

CREATE CAST (ext_lang.lang AS text)
WITH FUNCTION ext_lang.to_text(ext_lang.lang)
AS ASSIGNMENT;

CREATE FUNCTION ext_lang.raw_hstore(ext_lang.lang)
RETURNS hstore
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT ext_lang.raw_text($1)::hstore
$$;

CREATE FUNCTION ext_lang.merge_lang(p_old ext_lang.lang, p_new ext_lang.lang)
RETURNS ext_lang.lang
LANGUAGE plpgsql
STABLE
STRICT
AS $$
DECLARE
    v_lang text;
    v_default text;
    v_old hstore;
    v_new hstore;
    v_new_text text;
BEGIN
    v_lang := ext_lang.get_lang();
    IF v_lang IS NULL THEN
        RAISE EXCEPTION 'ext_lang.current is not set';
    END IF;

    v_default := ext_lang.default_lang();
    v_old := ext_lang.raw_hstore(p_old);
    v_new := ext_lang.raw_hstore(p_new);
    v_new_text := COALESCE(v_new -> v_lang, v_new -> '__default', ext_lang._localize(v_new, v_lang));

    v_old := v_old || hstore(v_lang, v_new_text);

    IF v_default = v_lang THEN
        v_old := v_old || hstore('__default', v_new_text);
    ELSIF (v_old -> '__default') IS NULL THEN
        v_old := v_old || hstore('__default', COALESCE(v_old -> v_default, v_new_text));
    END IF;

    RETURN ext_lang.from_hstore_text(v_old::text);
END;
$$;

CREATE FUNCTION ext_lang.u(p_old ext_lang.lang, p_new_text text)
RETURNS ext_lang.lang
LANGUAGE sql
STABLE
STRICT
AS $$
    SELECT ext_lang.merge_lang($1, ext_lang.from_text($2))
$$;
