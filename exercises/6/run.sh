#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"

echo "Подготовка тестовых данных..."

sudo -iu "$DB_USER" psql -X -v ON_ERROR_STOP=1 -d "$DB" <<'SQL'

DROP TABLE IF EXISTS public.motion_a;
DROP TABLE IF EXISTS public.motion_b;

CREATE TABLE public.motion_a
(
    id       bigint,
    join_key bigint,
    payload  text
)
DISTRIBUTED BY (id);

CREATE TABLE public.motion_b
(
    id       bigint,
    join_key bigint,
    payload  text
)
DISTRIBUTED BY (id);

INSERT INTO public.motion_a
SELECT
    i,
    (i * 37) % 5000000,
    repeat(md5(i::text), 4)
FROM generate_series(1, 5000000) i;

INSERT INTO public.motion_b
SELECT
    i,
    (i * 53) % 5000000,
    repeat(md5((i + 10000000)::text), 4)
FROM generate_series(1, 5000000) i;

ANALYZE public.motion_a;
ANALYZE public.motion_b;

SQL

echo "Подготовка завершена"
echo "Приступайте к заданию"
