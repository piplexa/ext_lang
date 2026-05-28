# Сборка DEB-пакета для ext_lang

Эта инструкция показывает, как упаковать расширение `ext_lang` в `.deb` для PostgreSQL 16 на Debian/Ubuntu.

Итоговый результат: пользователь сможет установить пакет командой вида:

```bash
sudo apt install ./postgresql-16-ext-lang_1.0-1_amd64.deb
```

Важно: команда `apt-get install postgresql-16-ext-lang` без локального файла начнет работать только после публикации пакета в APT-репозитории.

## 1. Требования

Установите инструменты сборки пакета:

```bash
sudo apt update
sudo apt install -y build-essential devscripts debhelper-compat postgresql-server-dev-16
```

## 2. Подготовка структуры `debian/`

В корне репозитория создайте файлы:

- `debian/control`
- `debian/rules`
- `debian/changelog`
- `debian/source/format`
- `debian/copyright`

### 2.1 `debian/control`

```debcontrol
Source: postgresql-16-ext-lang
Section: database
Priority: optional
Maintainer: Your Name <you@example.com>
Build-Depends: debhelper-compat (= 13), postgresql-server-dev-16
Standards-Version: 4.6.2
Rules-Requires-Root: no

Package: postgresql-16-ext-lang
Architecture: any
Depends: ${misc:Depends}, ${shlibs:Depends}, postgresql-16
Description: ext_lang extension for PostgreSQL 16
 PostgreSQL extension for localized text storage with hstore-backed payload.
```

### 2.2 `debian/rules`

```make
#!/usr/bin/make -f

export PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config

%:
	dh $@

override_dh_auto_build:
	$(MAKE) -C ext_lang PG_CONFIG=$(PG_CONFIG)

override_dh_auto_install:
	$(MAKE) -C ext_lang install \
		PG_CONFIG=$(PG_CONFIG) \
		DESTDIR=$(CURDIR)/debian/postgresql-16-ext-lang
```

Сделайте файл исполняемым:

```bash
chmod +x debian/rules
```

### 2.3 `debian/changelog`

```text
postgresql-16-ext-lang (1.0-1) unstable; urgency=medium

  * Initial release.

 -- Your Name <you@example.com>  Tue, 26 May 2026 12:00:00 +0000
```

### 2.4 `debian/source/format`

```text
3.0 (native)
```

### 2.5 `debian/copyright`

```text
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ext_lang
Source: https://example.com/ext_lang

Files: *
Copyright: 2026 Your Name
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction...
```

## 3. Сборка пакета

Из корня репозитория:

```bash
dpkg-buildpackage -us -uc -b
```

Результат появится на уровень выше, например:

```text
../postgresql-16-ext-lang_1.0-1_amd64.deb
```

## 4. Установка и проверка

Установите пакет:

```bash
sudo apt install ./../postgresql-16-ext-lang_1.0-1_amd64.deb
```

Подключите расширения в нужной базе:

```sql
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS ext_lang;
```

Проверьте:

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('hstore', 'ext_lang')
ORDER BY extname;
```

## 5. Как перейти к установке через `apt-get install`

Чтобы пользователь мог ставить пакет без локального файла:

1. Публикуйте `.deb` в APT-репозитории (например, на базе `aptly` или `reprepro`).
2. Добавьте репозиторий и ключ на клиентские машины.
3. После `apt update` установка станет доступна как:

```bash
sudo apt install postgresql-16-ext-lang
```

## 6. Замечания по версиям PostgreSQL

- Обычно нужен отдельный пакет на каждую major-версию PostgreSQL (`16`, `17`, ...).
- Имя пакета удобно держать в формате `postgresql-<major>-ext-lang`.
- Версия dev-пакета при сборке должна совпадать с целевой версией PostgreSQL.
