#!/bin/bash
set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

MDW=$(hostname -f)
ADCM=$(echo "$MDW" | sed 's/-mdw/-adcm/g')

# Определяем имя контейнера
CONTAINER_NAME="adcm-postgres"

echo "Поломка запущена..."

# Проверяем доступность ADCM
if ! ssh -q $SSH_OPTS "$ADCM" "exit" 2>/dev/null; then
    echo "Хост ADCM не доступен, свяжитесь с организаторами"
    exit 1
fi

# Выполняем команды на ADCM через SSH
ssh $SSH_OPTS "$ADCM" "
    # Проверяем, существует ли контейнер
    if ! sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^${CONTAINER_NAME}$'; then
        echo 'При развертке кластера, что-то пошло не так. Свяжитесь с организаторами'
        exit 0
    fi

    # Получаем ID контейнера
    CONTAINER_ID=\$(sudo docker ps -a --filter 'name=${CONTAINER_NAME}' --format '{{.ID}}' 2>/dev/null)
    
    # Проверяем статус контейнера
    STATUS=\$(sudo docker inspect -f '{{.State.Status}}' \"\$CONTAINER_ID\" 2>/dev/null)

    if [ \"\$STATUS\" != 'running' ]; then
        echo 'Приступайте к заданию'
        exit 0
    fi

    # Останавливаем контейнер
    echo 'Выполняем поломку'
    sudo docker stop \"\$CONTAINER_ID\" > /dev/null 2>&1

    # Проверяем результат
    NEW_STATUS=\$(sudo docker inspect -f '{{.State.Status}}' \"\$CONTAINER_ID\" 2>/dev/null)

    if [ \"\$NEW_STATUS\" = 'exited' ] || [ \"\$NEW_STATUS\" = 'stopped' ]; then
        echo 'Приступайте к заданию'
    else
        echo 'Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами'
        exit 1
    fi
"

echo "Скрипт завершён"
