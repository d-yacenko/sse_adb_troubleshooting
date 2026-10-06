#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

echo "Подготовка проблемной ситуации..."

# Берем любой работающий mirror прямо из каталога кластера.
MIRROR_INFO=$(sudo -iu "$DB_USER" psql -X -Atq -F '|' -d "$DB" -c "
SELECT hostname, datadir
FROM gp_segment_configuration
WHERE role='m' AND status='u'
ORDER BY content
LIMIT 1;")

if [ -z "$MIRROR_INFO" ]; then
    echo "Не удалось определить mirror-сегмент, свяжитесь с организаторами"
    exit 1
fi

IFS='|' read -r MIRROR_HOST MIRROR_DIR <<< "$MIRROR_INFO"

if ! ssh -q $SSH_OPTS "$MIRROR_HOST" "exit" 2>/dev/null; then
    echo "Хост mirror-сегмента недоступен, свяжитесь с организаторами"
    exit 1
fi

# Находим postmaster выбранного mirror по его data directory.
POSTMASTER_PID=$(ssh $SSH_OPTS "$MIRROR_HOST" \
    "ps -eo pid=,args= | grep '[p]ostgres -D $MIRROR_DIR ' | awk 'NR==1 {print \$1}'" 2>/dev/null || true)

if ! [[ "$POSTMASTER_PID" =~ ^[0-9]+$ ]]; then
    echo "Не удалось определить процесс mirror-сегмента, свяжитесь с организаторами"
    exit 1
fi

# Находим wal receiver — именно его остановка воспроизводит проблему.
WALR_PID=$(ssh $SSH_OPTS "$MIRROR_HOST" \
    "ps -eo pid=,ppid=,cmd= | awk -v p='$POSTMASTER_PID' '\$2==p && /wal receiver/ {print \$1; exit}'" 2>/dev/null || true)

if ! [[ "$WALR_PID" =~ ^[0-9]+$ ]]; then
    echo "Не удалось определить процесс репликации, свяжитесь с организаторами"
    exit 1
fi

# Повторный запуск: сначала возвращаем receiver в работу.
STATE=$(ssh $SSH_OPTS "$MIRROR_HOST" "ps -o stat= -p '$WALR_PID'" 2>/dev/null | tr -d '[:space:]' || true)
if [[ "$STATE" == *T* ]]; then
    ssh $SSH_OPTS "$MIRROR_HOST" "sudo kill -CONT '$WALR_PID'"
    sleep 2
fi

# Таблица для воспроизведения зависания INSERT.
sudo -iu "$DB_USER" psql -X -v ON_ERROR_STOP=1 -d "$DB" <<'SQL' >/dev/null
DROP TABLE IF EXISTS public.write_test;
CREATE TABLE public.write_test
(
    id bigint,
    payload text
)
WITH (appendonly=false)
DISTRIBUTED RANDOMLY;
SQL

# Останавливаем только wal receiver.
ssh $SSH_OPTS "$MIRROR_HOST" "sudo kill -STOP '$WALR_PID'"
sleep 1

STATE=$(ssh $SSH_OPTS "$MIRROR_HOST" "ps -o stat= -p '$WALR_PID'" 2>/dev/null | tr -d '[:space:]' || true)
if [[ "$STATE" != *T* ]]; then
    echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
    exit 1
fi

echo "Приступайте к заданию"
