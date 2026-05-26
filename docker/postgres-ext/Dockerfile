FROM postgres:16

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential postgresql-server-dev-16 \
    && rm -rf /var/lib/apt/lists/*

COPY ext_lang /usr/local/src/ext_lang
RUN make -C /usr/local/src/ext_lang \
    && make -C /usr/local/src/ext_lang install \
    && rm -rf /usr/local/src/ext_lang
