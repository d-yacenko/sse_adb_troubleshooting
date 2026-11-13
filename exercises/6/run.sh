#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
LOSS="0.06"
TAG="exercise6_loss"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

MSDW=$(hostname -f)
[[ "${MSDW%%.*}" == *-msdw1 ]] || { echo "Запустите упражнение на msdw1"; exit 1; }
SDW1=$(echo "$MSDW" | sed 's/-msdw1/-sdw1/')
SDW2=$(echo "$MSDW" | sed 's/-msdw1/-sdw2/')

echo "Подготовка тестовых данных..."

for HOST in "$SDW1" "$SDW2"; do
    ssh $SSH_OPTS "$HOST" "
        while N=\$(sudo iptables -L OUTPUT --line-numbers -n | awk '/$TAG/{print \$1; exit}'); [ -n \"\$N\" ]; do
            sudo iptables -D OUTPUT \"\$N\"
        done
    "
done

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
SELECT i, (i * 37) % 5000000, repeat(md5(i::text), 4)
FROM generate_series(1, 5000000) i;

INSERT INTO public.motion_b
SELECT i, (i * 53) % 5000000, repeat(md5((i + 10000000)::text), 4)
FROM generate_series(1, 5000000) i;

ANALYZE public.motion_a;
ANALYZE public.motion_b;
SQL

for HOST in "$SDW1" "$SDW2"; do
    for PROTO in udp tcp; do
        ssh $SSH_OPTS "$HOST"             "sudo iptables -I OUTPUT 1 -p $PROTO -m owner --uid-owner $DB_USER              -m statistic --mode random --probability $LOSS              -m comment --comment $TAG -j DROP"
    done
done

echo "Подготовка завершена"
echo "Приступайте к заданию"
