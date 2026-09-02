#!/bin/bash
set -euo pipefail

# Определяем имя контейнера
CONTAINER_NAME="adcm-postgres"

# Проверяем, существует ли контейнер
if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "При развертке кластера, что-то пошло не так. Свяжитесь с организаторами"
    exit 0
fi

# Получаем ID контейнера
CONTAINER_ID=$(sudo docker ps -a --filter "name=${CONTAINER_NAME}" --format '{{.ID}}')

# Проверяем статус контейнера
STATUS=$(sudo docker inspect -f '{{.State.Status}}' "$CONTAINER_ID")

if [ "$STATUS" != "running" ]; then
    echo "Приступайте к заданию"
    exit 0
fi

# Останавливаем контейнер
echo "Выполняем поломку"
sudo docker stop "$CONTAINER_ID" > /dev/null 2>&1

# Проверяем результат
NEW_STATUS=$(sudo docker inspect -f '{{.State.Status}}' "$CONTAINER_ID")

if [ "$NEW_STATUS" = "exited" ] || [ "$NEW_STATUS" = "stopped" ]; then
    echo "Приступайте к заданию"
else
    echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
    exit 1
fi