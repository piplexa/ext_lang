\set ON_ERROR_STOP on

-- ext_lang smoke test: basic install contract and data flow.
CREATE EXTENSION IF NOT EXISTS ext_lang;

SELECT ext_lang.add_language('ru_RU', false);
SELECT ext_lang.set_lang('ru_RU');

DROP TABLE IF EXISTS article;
CREATE TABLE article (
    id serial PRIMARY KEY,
    title ext_lang.lang,
    views integer NOT NULL DEFAULT 0
);

INSERT INTO article (title, views) VALUES ('привет', 10);

-- Non-language UPDATE should not affect translation payload.
UPDATE article SET views = 11 WHERE id = 1;

SELECT ext_lang.set_lang('en_US');
UPDATE article
SET title = ext_lang.u(title, 'hello')
WHERE id = 1;

-- Assertions.
DO $$
DECLARE
    v_raw hstore;
    v_title_ru text;
    v_title_en text;
BEGIN
    SELECT ext_lang.raw_hstore(title) INTO v_raw
    FROM article
    WHERE id = 1;

    IF (v_raw -> 'ru_RU') IS DISTINCT FROM 'привет' THEN
        RAISE EXCEPTION 'Expected ru_RU translation to be "привет", got %', v_raw -> 'ru_RU';
    END IF;

    IF (v_raw -> 'en_US') IS DISTINCT FROM 'hello' THEN
        RAISE EXCEPTION 'Expected en_US translation to be "hello", got %', v_raw -> 'en_US';
    END IF;

    IF (v_raw -> '__default') IS DISTINCT FROM 'hello' THEN
        RAISE EXCEPTION 'Expected __default to be "hello", got %', v_raw -> '__default';
    END IF;

    PERFORM ext_lang.set_lang('ru_RU');
    SELECT title::text INTO v_title_ru FROM article WHERE id = 1;
    IF v_title_ru IS DISTINCT FROM 'привет' THEN
        RAISE EXCEPTION 'Expected localized RU title "привет", got %', v_title_ru;
    END IF;

    PERFORM ext_lang.set_lang('en_US');
    SELECT title::text INTO v_title_en FROM article WHERE id = 1;
    IF v_title_en IS DISTINCT FROM 'hello' THEN
        RAISE EXCEPTION 'Expected localized EN title "hello", got %', v_title_en;
    END IF;
END;
$$;

SELECT 'smoke_test_ok' AS result;
