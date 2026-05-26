# ext_lang

Граждане! Храните переводы в базе данных! Это удобно и легко.

Расширение PostgreSQL для хранения локализованного текста с:
- прозрачными SELECT и INSERT для типа ext_lang.lang;
- явным UPDATE через одну функцию ext_lang.u(...);
- хранением переводов в hstore с fallback-логикой.

## Структура репозитория

- ext_lang/ - исходники расширения (C + SQL + control)
- docker/ - сборка образа PostgreSQL с установленным расширением
- initdb_ext_lang/ - init-скрипты активной реализации
- initdb/ - legacy backup (для справки, не используется рантаймом)
- tests/ - smoke-тесты
- docs/ - техническая документация

## Требования

- Docker + Docker Compose

Все варианты установки (Docker и локальная установка без Docker) описаны в [INSTALL.ru.md](INSTALL.ru.md).

## TL;DR Локальная установка (без Docker)

```bash
sudo apt update && sudo apt install -y build-essential postgresql-server-dev-16
cd ext_lang && make && sudo make install
psql -d <db_name> -c "CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS ext_lang;"
```

## Быстрый старт

1. Сборка и запуск БД с чистого состояния:

```bash
docker compose down -v
docker compose up -d --build
```

2. Проверка установки расширения:

```bash
docker compose exec -T postgres psql -U postgres -d app -c "SELECT extname FROM pg_extension ORDER BY 1;"
```

В результате должен присутствовать ext_lang.

## Использование

### 1) Создание таблицы

```sql
CREATE TABLE article (
    id serial PRIMARY KEY,
    title ext_lang.lang,
    views integer NOT NULL DEFAULT 0
);
```

### 2) Настройка языков и языка сессии

```sql
SELECT ext_lang.add_language('ru_RU', false);
SELECT ext_lang.set_lang('ru_RU');
```

### 3) Вставка (прозрачно)

```sql
INSERT INTO article (title, views) VALUES ('привет', 10);
```

### 4) Чтение (прозрачно)

```sql
SELECT id, title, views FROM article;
```

### 5) Обновление не-языковых полей (без overhead ext_lang)

```sql
UPDATE article SET views = 11 WHERE id = 1;
```

### 6) Обновление языкового поля (явная merge-функция)

```sql
SELECT ext_lang.set_lang('en_US');
UPDATE article SET title = ext_lang.u(title, 'hello') WHERE id = 1;
```

## Справочник функций

Публичный API:

- ext_lang.add_language(code text, is_default boolean default false)
  - Регистрирует новый язык или повторно активирует существующий.
  - Если is_default=true, делает язык языком по умолчанию.

- ext_lang.set_lang(lang text)
  - Устанавливает язык текущей сессии (GUC ext_lang.current).

- ext_lang.get_lang()
  - Возвращает активный язык сессии или NULL.

- ext_lang.default_lang()
  - Возвращает язык по умолчанию.

- ext_lang.u(old_value ext_lang.lang, new_text text)
  - Функция UPDATE для языковых колонок.
  - Обновляет перевод только для текущего языка сессии.
  - Сохраняет переводы на остальных языках.

- ext_lang.from_text(value text)
  - Преобразует обычный текст в ext_lang.lang для текущего языка сессии.

- ext_lang.to_text(value ext_lang.lang)
  - Возвращает локализованный текст с учетом fallback.

- ext_lang.raw_hstore(value ext_lang.lang)
  - Возвращает сырой hstore (для отладки и инспекции).

Внутренние helper-функции:

- ext_lang._validate_lang(lang text)
  - Валидирует язык (существует и активен).

- ext_lang._from_input_text(value text)
  - Формирует начальный hstore payload из текстового значения.

- ext_lang._localize(store hstore, lang text default null)
  - Выбирает локализованное значение по fallback-цепочке.

- ext_lang.merge_lang(old_value ext_lang.lang, new_value ext_lang.lang)
  - Сливает новый перевод в существующий payload.

- ext_lang.raw_text(value ext_lang.lang)
  - Возвращает текстовую форму внутреннего hstore.

- ext_lang.from_hstore_text(value text)
  - Восстанавливает ext_lang.lang из сырого hstore-текста.

## Fallback-порядок

Путь чтения:
1. текущий язык сессии
2. язык по умолчанию
3. ключ __default
4. первое доступное значение в hstore

## Smoke-тест

Запуск из корня репозитория:

```bash
docker compose exec -T postgres psql -U postgres -d app < tests/smoke_test.sql
```

Ожидаемая финальная строка:

```text
smoke_test_ok
```

## Примечания

- Активный init-каталог: initdb_ext_lang.
- Legacy backup в initdb сохранен намеренно и не подгружается при старте контейнера.
- Реализация не зависит от функций из initdb/02-ext-lang.sql.
