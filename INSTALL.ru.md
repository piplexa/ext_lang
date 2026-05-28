# Руководство по установке

English version: [INSTALL.md](INSTALL.md)

В этом документе собраны все поддерживаемые способы установки PostgreSQL-расширения `ext_lang`.

## Содержание

- [Требования](#требования)
- [Вариант A: Docker (рекомендуется для быстрого старта)](#вариант-a-docker-рекомендуется-для-быстрого-старта)
- [Вариант B: Локальная сборка из исходников (без Docker)](#вариант-b-локальная-сборка-из-исходников-без-docker)
- [Вариант C: Несколько версий PostgreSQL на одном хосте](#вариант-c-несколько-версий-postgresql-на-одном-хосте)
- [Сборка DEB-пакета](#сборка-deb-пакета)
- [Подключение расширения в базе](#подключение-расширения-в-базе)
- [Проверка установки](#проверка-установки)
- [Устранение проблем](#устранение-проблем)

## Требования

- PostgreSQL 16 (или другая поддерживаемая версия, с соответствующими dev-заголовками)
- C toolchain (`gcc` или `clang`), `make`
- Пакет разработки PostgreSQL server (`pg_config` должен быть доступен)
- Расширение `hstore` в целевой базе (обязательная зависимость для `ext_lang`)

Проект использует систему сборки PGXS:
- модуль: [ext_lang/ext_lang.c](ext_lang/ext_lang.c)
- файл сборки: [ext_lang/Makefile](ext_lang/Makefile)
- control-файл: [ext_lang/ext_lang.control](ext_lang/ext_lang.control)

## Вариант A: Docker (рекомендуется для быстрого старта)

В репозитории уже есть конфигурация Docker, которая собирает и устанавливает расширение в образ PostgreSQL:
- [docker/postgres-ext/Dockerfile](docker/postgres-ext/Dockerfile)
- [docker-compose.yaml](docker-compose.yaml)

Из корня репозитория:

```bash
docker compose down -v
docker compose up -d --build
```

## Вариант B: Локальная сборка из исходников (без Docker)

### Пример для Debian/Ubuntu (PostgreSQL 16)

```bash
sudo apt update
sudo apt install -y build-essential postgresql-server-dev-16
```

### Сборка и установка

Выполнить из корня репозитория:

```bash
cd ext_lang
make
sudo make install
```

В результате устанавливаются:
- shared library в libdir PostgreSQL
- SQL/control файлы расширения в каталог extensions PostgreSQL

## Вариант C: Несколько версий PostgreSQL на одном хосте

Если на хосте установлено несколько версий PostgreSQL, явно укажите `PG_CONFIG`.

Пример для PostgreSQL 16:

```bash
cd ext_lang
make PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
sudo make install PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
```

Проверка выбранного toolchain:

```bash
/usr/lib/postgresql/16/bin/pg_config --version
/usr/lib/postgresql/16/bin/pg_config --pkglibdir
/usr/lib/postgresql/16/bin/pg_config --sharedir
```

## Сборка DEB-пакета

Пошаговая инструкция по созданию `.deb`-пакета вынесена в отдельный документ:
[docs/DEB_PACKAGING.ru.md](docs/DEB_PACKAGING.ru.md)

## Подключение расширения в базе

Подключитесь к нужной БД и выполните:

```sql
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS ext_lang;
```

## Проверка установки

В `psql`:

```sql
\dx
```

Или SQL-проверкой:

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('hstore', 'ext_lang')
ORDER BY extname;
```

Быстрая smoke-проверка:

```sql
SELECT ext_lang.default_lang();
```

Ожидаемо: одна строка с языком по умолчанию (для новой установки обычно `en_US`).

## Устранение проблем

1. `pg_config` не найден
- Установите dev-пакет PostgreSQL.
- Проверьте, что нужный `pg_config` в `PATH`, или передайте явный `PG_CONFIG=...`.

2. Сборка прошла, но `CREATE EXTENSION ext_lang` падает с “could not open extension control file”
- Чаще всего причина: сборка/установка выполнены для версии PostgreSQL, отличной от версии запущенного сервера.
- Пересоберите с корректным `PG_CONFIG`.

3. `permission denied` при `make install`
- Шаг установки пишет в системные каталоги PostgreSQL и обычно требует прав root:
  - `sudo make install`

4. `required extension "hstore" is not installed`
- Выполните:
  - `CREATE EXTENSION hstore;`
  - затем `CREATE EXTENSION ext_lang;`

5. Названия пакетов в дистрибутиве отличаются
- Для не-Debian систем установите эквивалент пакета разработки PostgreSQL server и build tools.
