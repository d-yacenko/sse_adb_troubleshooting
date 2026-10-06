#!/bin/bash
set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

# Определяем имена хостов
MDW=$(hostname -f)
MSDW=$(echo "$MDW" | sed 's/-mdw/-msdw/g')

echo "Поломка запущена..."

# 1. Проверяем доступность MSDW
if ssh -q $SSH_OPTS "$MSDW" "exit" 2>/dev/null; then
    echo "..."

    # Устанавливаем параметры через gpconfig
        ssh $SSH_OPTS "$MSDW" "
        sudo su - gpadmin << 'EOF'
            set -e
            gpconfig -c 'gp_default_storage_options' -v 'appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5' > /dev/null 2>&1
            psql -d postgres -c \"ALTER DATABASE postgres SET search_path = task, pg_catalog\" > /dev/null 2>&1
            psql -d adb -c \"ALTER DATABASE adb SET search_path = task, pg_catalog\" > /dev/null 2>&1
            gpconfig -c default_transaction_read_only -v on > /dev/null 2>&1
            gpstop -u > /dev/null 2>&1
EOF
    "

    echo "Приступайте к заданию"
else
    echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
    exit 1
fi