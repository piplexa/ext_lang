#include "postgres.h"

#include "executor/spi.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(ext_lang_in);
PG_FUNCTION_INFO_V1(ext_lang_out);
PG_FUNCTION_INFO_V1(ext_lang_from_text);
PG_FUNCTION_INFO_V1(ext_lang_to_text);
PG_FUNCTION_INFO_V1(ext_lang_raw_text);
PG_FUNCTION_INFO_V1(ext_lang_from_hstore_text);

static text *
spi_text1(const char *sql, text *arg)
{
    Oid argtypes[1] = {TEXTOID};
    Datum values[1];
    char nulls[1] = {' '};
    SPIPlanPtr plan;
    int spi_rc;
    bool isnull;
    Datum d;
    text *result;
    MemoryContext caller_ctx = CurrentMemoryContext;

    values[0] = PointerGetDatum(arg);

    spi_rc = SPI_connect();
    if (spi_rc != SPI_OK_CONNECT)
        ereport(ERROR, (errmsg("SPI_connect failed: %d", spi_rc)));

    plan = SPI_prepare(sql, 1, argtypes);
    if (plan == NULL)
        ereport(ERROR, (errmsg("SPI_prepare failed for: %s", sql)));

    spi_rc = SPI_execute_plan(plan, values, nulls, true, 1);
    if (spi_rc != SPI_OK_SELECT)
        ereport(ERROR, (errmsg("SPI_execute_plan failed: %d", spi_rc)));

    if (SPI_processed != 1)
        ereport(ERROR, (errmsg("expected one row, got %llu", (unsigned long long) SPI_processed)));

    d = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
    if (isnull)
    {
        SPI_finish();
        return NULL;
    }

    {
        MemoryContext old_ctx;

        old_ctx = MemoryContextSwitchTo(caller_ctx);
        result = cstring_to_text(text_to_cstring(DatumGetTextPP(d)));
        MemoryContextSwitchTo(old_ctx);
    }

    spi_rc = SPI_finish();
    if (spi_rc != SPI_OK_FINISH)
        ereport(ERROR, (errmsg("SPI_finish failed: %d", spi_rc)));

    return result;
}

Datum
ext_lang_from_text(PG_FUNCTION_ARGS)
{
    text *input = PG_GETARG_TEXT_PP(0);
    text *stored;

    stored = spi_text1("SELECT ext_lang._from_input_text($1)::text", input);
    if (stored == NULL)
        PG_RETURN_NULL();

    PG_RETURN_TEXT_P(stored);
}

Datum
ext_lang_to_text(PG_FUNCTION_ARGS)
{
    text *raw = PG_GETARG_TEXT_PP(0);
    text *localized;

    localized = spi_text1("SELECT ext_lang._localize(($1)::hstore)", raw);
    if (localized == NULL)
        PG_RETURN_NULL();

    PG_RETURN_TEXT_P(localized);
}

Datum
ext_lang_raw_text(PG_FUNCTION_ARGS)
{
    text *raw = PG_GETARG_TEXT_PP(0);

    PG_RETURN_TEXT_P(cstring_to_text(text_to_cstring(raw)));
}

Datum
ext_lang_from_hstore_text(PG_FUNCTION_ARGS)
{
    text *raw = PG_GETARG_TEXT_PP(0);

    PG_RETURN_TEXT_P(cstring_to_text(text_to_cstring(raw)));
}

Datum
ext_lang_in(PG_FUNCTION_ARGS)
{
    char *input = PG_GETARG_CSTRING(0);
    text *t_input = cstring_to_text(input);
    text *stored;

    stored = spi_text1("SELECT ext_lang._from_input_text($1)::text", t_input);
    if (stored == NULL)
        PG_RETURN_NULL();

    PG_RETURN_TEXT_P(stored);
}

Datum
ext_lang_out(PG_FUNCTION_ARGS)
{
    text *raw = PG_GETARG_TEXT_PP(0);
    text *localized;

    localized = spi_text1("SELECT ext_lang._localize(($1)::hstore)", raw);
    if (localized == NULL)
        PG_RETURN_CSTRING(pstrdup(""));

    PG_RETURN_CSTRING(text_to_cstring(localized));
}
