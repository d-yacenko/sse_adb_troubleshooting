#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

SDW2=$(hostname -f | sed 's/-mdw/-sdw2/')

echo "Подготовка проблемной ситуации..."

# На sdw2 должно быть два wal receiver.
PIDS=$(ssh $SSH_OPTS "$SDW2" \
    "ps -eo pid=,args= | awk '/[w]al receiver process/ {print \$1}' | xargs")

if [ "$(wc -w <<< "$PIDS")" -ne 2 ]; then
    echo "Не удалось определить два процесса wal receiver"
    exit 1
fi

# На случай повторного запуска сначала возвращаем их в работу.
ssh $SSH_OPTS "$SDW2" "sudo kill -CONT $PIDS"
sleep 2

# Подготавливаем таблицу на исправном кластере.
sudo -iu "$DB_USER" psql -X -v ON_ERROR_STOP=1 -d "$DB" -c \
"DROP TABLE IF EXISTS public.write_test;
 CREATE TABLE public.write_test (id bigint, payload text)
 WITH (appendonly=false) DISTRIBUTED RANDOMLY;" >/dev/null

# Создаем неисправность: останавливаем оба wal receiver на хосте.
ssh $SSH_OPTS "$SDW2" "sudo kill -STOP $PIDS"
sleep 1

for PID in $PIDS; do
    STATE=$(ssh $SSH_OPTS "$SDW2" "ps -o stat= -p '$PID'" | tr -d '[:space:]')
    [[ "$STATE" == *T* ]] || {
        echo "Не удалось остановить процессы wal receiver"
        exit 1
    }
done

echo "Приступайте к заданию"
