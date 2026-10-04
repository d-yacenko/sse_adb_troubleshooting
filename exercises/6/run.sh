#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
RESOURCE_GROUP="admin_group"

APP_PREFIX="exercise6_resgroup"
SLEEP_SECONDS=$((240 * 3600))
LOG_FILE="/tmp/${APP_PREFIX}.log"

echo "Поломка запущена..."

# Проверяем, что кластер использует resource groups
RESOURCE_MANAGER=$(sudo -iu "$DB_USER" \
    psql -X -Atq -d "$DB" \
    -c "SHOW gp_resource_manager;")

if [ "$RESOURCE_MANAGER" != "group" ]; then
    echo "В кластере не используются resource groups. Свяжитесь с организаторами"
    exit 1
fi

# Проверяем ресурсную группу gpadmin
GPADMIN_GROUP=$(sudo -iu "$DB_USER" \
    psql -X -Atq -d "$DB" \
    -c "
        SELECT r.rsgname
        FROM pg_roles u
        JOIN pg_resgroup r
          ON r.oid = u.rolresgroup
        WHERE u.rolname = 'gpadmin';
    ")

if [ "$GPADMIN_GROUP" != "$RESOURCE_GROUP" ]; then
    echo "Пользователь gpadmin находится не в ${RESOURCE_GROUP}. Свяжитесь с организаторами"
    exit 1
fi

# Получаем текущий concurrency admin_group
CONCURRENCY=$(sudo -iu "$DB_USER" \
    psql -X -Atq -d "$DB" \
    -c "
        SELECT concurrency::int
        FROM gp_toolkit.gp_resgroup_config
        WHERE groupname = '${RESOURCE_GROUP}';
    ")

if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || [ "$CONCURRENCY" -le 0 ]; then
    echo "Не удалось определить concurrency ресурсной группы. Свяжитесь с организаторами"
    exit 1
fi

WORKERS=$((CONCURRENCY + 1))

echo "Подготовка проблемной ситуации..."
: > "$LOG_FILE"

# Занимаем все concurrency slots и создаем еще один запрос в очереди.
# nohup позволяет запросам продолжить работу после закрытия терминала.
for i in $(seq 1 "$WORKERS"); do
    nohup sudo -iu "$DB_USER" \
        psql -X \
        -d "dbname=${DB} application_name=${APP_PREFIX}_${i}" \
        -c "SELECT pg_sleep(${SLEEP_SECONDS}) FROM gp_dist_random('gp_id');" \
        >> "$LOG_FILE" 2>&1 < /dev/null &
done

sleep 3

echo "Приступайте к заданию"
