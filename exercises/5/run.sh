#!/bin/bash
set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

# Определяем имена хостов
MDW=$(hostname -f)
STANDBY=(echo "$MDW" | sed 's/-mdw/-msdw/g')


# 1. Проверяем доступность MDW
if ssh -q $SSH_OPTS "$MDW" "exit" 2>/dev/null; then
    echo "Первый этап запущен"
    ssh $SSH_OPTS "$MDW" "sudo pkill -9 -f 'postgres' 2>/dev/null; sudo rm -f /tmp/.s.PGSQL.5432*" 2>/dev/null || true
    
    sleep 2
    
    # Проверяем, что процесс остановлен
    PG_RUNNING=$(ssh $SSH_OPTS "$MDW" "ps aux | grep -E '[p]ostgres' | grep -v grep | wc -l" 2>/dev/null || echo "0")
    if [ "$PG_RUNNING" -gt 0 ]; then
        echo "Проверка"
        ssh $SSH_OPTS "$MDW" "ps aux | grep -E '[p]ostgres' | grep -v grep" 2>/dev/null
        echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
        exit 1
    fi
    
    echo "Первый этап завершен"
else
    echo "Хост мастера вышел из строя"
fi

# 2. Проверяем доступность standby
if ! ssh -q $SSH_OPTS "$STANDBY" "exit" 2>/dev/null; then
    echo "Хост standby-мастера не доступен, свяжитесь с организаторами"
    exit 1
fi

# 3. Очищаем standby
echo "Второй этап запущен"
ssh $SSH_OPTS "$STANDBY" "sudo pkill -9 -f 'postgres.*master' 2>/dev/null; sudo rm -f /tmp/.s.PGSQL.5432*" 2>/dev/null || true

echo "Второй этап завершен"

echo ""
echo "Приступайте к заданию"