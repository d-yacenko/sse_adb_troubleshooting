#!/bin/bash
set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

MDW=$(hostname -f)
STANDBY=$(echo "$MDW" | sed 's/-mdw/-msdw1/g')

# Проверяем доступность standby до вмешательства в работающий master.
if ! ssh -q $SSH_OPTS "$STANDBY" "exit" 2>/dev/null; then
    echo "Хост standby-мастера недоступен, свяжитесь с организаторами"
    exit 1
fi

echo "Первый этап запущен"

# Блокируем повторный запуск postgres ТОЛЬКО на старом mdw.
# Уже работающий postmaster после chmod продолжит работать до остановки.
ssh $SSH_OPTS "$MDW" 'sudo bash -s' <<'EOF'
set -euo pipefail
MASTER_DIR=/data1/master/gpseg-1
MODE_FILE=/root/exercise4_postgres_original_mode

PID=$(head -n 1 "$MASTER_DIR/postmaster.pid")
if ! [[ "$PID" =~ ^[0-9]+$ ]] || [ ! -e "/proc/$PID/exe" ]; then
    echo "Не удалось определить работающий master"
    exit 1
fi

POSTGRES_BIN=$(readlink -f "/proc/$PID/exe")
if [ "$(basename "$POSTGRES_BIN")" != "postgres" ] || [ ! -x "$POSTGRES_BIN" ]; then
    echo "Не удалось определить исполняемый файл postgres"
    exit 1
fi

# Сохраняем первоначальные права для возможного отката.
if [ ! -e "$MODE_FILE" ]; then
    printf '%s\n%s\n' "$POSTGRES_BIN" "$(stat -c '%a' "$POSTGRES_BIN")" > "$MODE_FILE"
fi
chmod a-x "$POSTGRES_BIN"
EOF

# Принудительно останавливаем процессы PostgreSQL старого mdw.
ssh $SSH_OPTS "$MDW" "sudo pkill -9 -u gpadmin -x postgres || true"
sleep 2

PG_RUNNING=$(ssh $SSH_OPTS "$MDW" "pgrep -u gpadmin -x postgres | wc -l")
if [ "$PG_RUNNING" -gt 0 ]; then
    echo "На старом master остались процессы postgres"
    exit 1
fi
echo "Первый этап завершен"

# Останавливаем standby перед принудительной активацией через ADCM.
echo "Второй этап запущен"
ssh $SSH_OPTS "$STANDBY" "sudo pkill -9 -u gpadmin -x postgres || true"
echo "Второй этап завершен"

# Удаляем оставшиеся сокеты.
echo "Третий этап запущен"
ssh $SSH_OPTS "$MDW" "sudo rm -f /tmp/.s.PGSQL.5432*"
ssh $SSH_OPTS "$STANDBY" "sudo rm -f /tmp/.s.PGSQL.5432*"
echo "Третий этап завершен"
echo "Приступайте к заданию"
