#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

MDW=$(hostname -f)
SDW1=$(echo "$MDW" | sed 's/-mdw/-sdw1/g')
SDW2=$(echo "$MDW" | sed 's/-mdw/-sdw2/g')

echo "Подготовка проблемной ситуации..."

# Таблицу создаем до остановки репликации.
sudo -iu "$DB_USER" psql -X -v ON_ERROR_STOP=1 -d "$DB" -c \
"DROP TABLE IF EXISTS public.write_test;
 CREATE TABLE public.write_test (id bigint, payload text)
 WITH (appendonly=false) DISTRIBUTED RANDOMLY;" >/dev/null

# Ищем segment-host, на котором видны оба wal receiver.
TARGET=""
PIDS=""

for HOST in "$SDW1" "$SDW2"; do
    if ! ssh -q $SSH_OPTS "$HOST" "exit" 2>/dev/null; then
        continue
    fi

    CUR_PIDS=$(ssh $SSH_OPTS "$HOST" \
        "ps -eo pid=,args= | awk '/[w]al receiver process/ {print \$1}'" \
        2>/dev/null || true)

    COUNT=$(wc -w <<< "$CUR_PIDS")

    if [ "$COUNT" -eq 2 ]; then
        TARGET="$HOST"
        PIDS="$CUR_PIDS"
        break
    fi
done

if [ -z "$TARGET" ]; then
    echo "Не удалось определить два процесса wal receiver"
    exit 1
fi

ssh $SSH_OPTS "$TARGET" "sudo kill -STOP $PIDS"
sleep 1

for PID in $PIDS; do
    STATE=$(ssh $SSH_OPTS "$TARGET" "ps -o stat= -p '$PID'" 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "$STATE" != *T* ]]; then
        echo "Не удалось остановить процесс wal receiver"
        exit 1
    fi
done

echo "Приступайте к заданию"
