#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

MDW=$(hostname -f)
SDW1=$(echo "$MDW" | sed 's/-mdw/-sdw1/g')

echo "Подготовка проблемной ситуации..."

# Проверяем доступность segment-host.
if ! ssh -q $SSH_OPTS "$SDW1" "exit" 2>/dev/null; then
    echo "Хост segment-сервера недоступен, свяжитесь с организаторами"
    exit 1
fi

# Выбираем работающий mirror на sdw1.
MIRROR_INFO=$(sudo -iu "$DB_USER" psql -X -Atq -F '|' -d "$DB" -c "
    SELECT datadir, content
    FROM gp_segment_configuration
    WHERE role = 'm'
      AND status = 'u'
      AND hostname = '$SDW1'
    ORDER BY content
    LIMIT 1;
")

if [ -z "$MIRROR_INFO" ]; then
    echo "Не удалось определить mirror-сегмент, свяжитесь с организаторами"
    exit 1
fi

IFS='|' read -r MIRROR_DIR CONTENT <<< "$MIRROR_INFO"

# Определяем postmaster выбранного mirror.
POSTMASTER_PID=$(ssh $SSH_OPTS "$SDW1" \
    "awk 'NR==1 {print \$1}' '$MIRROR_DIR/postmaster.pid'" 2>/dev/null || true)

if ! [[ "$POSTMASTER_PID" =~ ^[0-9]+$ ]]; then
    echo "Не удалось определить процесс mirror-сегмента, свяжитесь с организаторами"
    exit 1
fi

# Находим wal receiver выбранного mirror.
WALR_PID=$(ssh $SSH_OPTS "$SDW1" \
    "ps -eo pid=,ppid=,stat=,cmd=" 2>/dev/null \
    | awk -v p="$POSTMASTER_PID" '$2 == p && /wal receiver/ {print $1; exit}')

if ! [[ "$WALR_PID" =~ ^[0-9]+$ ]]; then
    echo "Не удалось определить процесс репликации, свяжитесь с организаторами"
    exit 1
fi

# Повторный запуск: если процесс уже остановлен, сначала возвращаем его в работу.
WALR_STATE=$(ssh $SSH_OPTS "$SDW1" \
    "ps -o stat= -p '$WALR_PID'" 2>/dev/null | tr -d '[:space:]' || true)

if [[ "$WALR_STATE" == *T* ]]; then
    ssh $SSH_OPTS "$SDW1" "kill -CONT '$WALR_PID'"
    sleep 3
fi

# Подготавливаем таблицу до создания проблемной ситуации.
sudo -iu "$DB_USER" psql -X -v ON_ERROR_STOP=1 -d "$DB" <<'SQL' >/dev/null
DROP TABLE IF EXISTS public.write_test;

CREATE TABLE public.write_test
(
    id      bigint,
    payload text
)
WITH (appendonly=false)
DISTRIBUTED RANDOMLY;
SQL

# Останавливаем только процесс приема репликационного потока mirror-сегмента.
ssh $SSH_OPTS "$SDW1" "kill -STOP '$WALR_PID'"
sleep 1

# Проверяем, что процесс действительно находится в stopped-состоянии.
WALR_STATE=$(ssh $SSH_OPTS "$SDW1" \
    "ps -o stat= -p '$WALR_PID'" 2>/dev/null | tr -d '[:space:]' || true)

if [[ "$WALR_STATE" != *T* ]]; then
    echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
    exit 1
fi

echo "Приступайте к заданию"
