#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

MDW=$(hostname -f)
SDW2=$(echo "$MDW" | sed 's/-mdw/-sdw2/g')

echo "Подготовка проблемной ситуации..."

if ! ssh -q $SSH_OPTS "$SDW2" "exit" 2>/dev/null; then
    echo "Хост segment-сервера недоступен, свяжитесь с организаторами"
    exit 1
fi

sudo -iu "$DB_USER" psql -X -v ON_ERROR_STOP=1 -d "$DB" -c "DROP TABLE IF EXISTS public.write_test; CREATE TABLE public.write_test (id bigint, payload text) WITH (appendonly=false) DISTRIBUTED RANDOMLY;" >/dev/null

ssh $SSH_OPTS "$SDW2" '
PIDS=$(pgrep -f "postgres: .*wal receiver process" || true)
COUNT=$(printf "%s\n" "$PIDS" | awk "NF{n++} END{print n+0}")

if [ "$COUNT" -ne 2 ]; then
    echo "Не удалось определить два процесса wal receiver"
    exit 1
fi

sudo kill -STOP $PIDS
sleep 1

for PID in $PIDS; do
    STATE=$(ps -o stat= -p "$PID" | tr -d "[:space:]")
    case "$STATE" in
        *T*) ;;
        *) echo "Не удалось остановить процесс wal receiver"; exit 1 ;;
    esac
done
'

echo "Приступайте к заданию"
