#!/bin/bash
set -euo pipefail

MDW=$(hostname)
SDW1=$(echo "$MDW" | sed 's/mdw/sdw1/g')

SSH_OPTS="-o StrictHostKeyChecking=accept-new"
TARGET_DIR="/data1/primary/gpseg0"

PID=$(ssh $SSH_OPTS "$SDW1" \
    "ps aux | awk '/[p]ostgres/ && /gpseg0/ {print \$2}'")

DIR=$(ssh $SSH_OPTS "$SDW1" \
    "if sudo test -d '$TARGET_DIR'; then echo '$TARGET_DIR'; fi")

if [ -z "$PID" ] && [ -z "$DIR" ]; then
    echo "Уже все готово, приступайте к заданию"
    exit 0
fi

# Убиваем postgres gpseg0, если он существует
if [ -n "$PID" ]; then
    ssh $SSH_OPTS "$SDW1" \
        "sudo kill -9 $PID"
fi

# Удаляем каталог gpseg0, если он существует
if [ -n "$DIR" ]; then
    ssh $SSH_OPTS "$SDW1" \
        "sudo rm -rf -- '$TARGET_DIR'"
fi

# Проверяем результат
PID_=$(ssh $SSH_OPTS "$SDW1" \
    "ps aux | awk '/[p]ostgres/ && /gpseg0/ {print \$2}'")

DIR_=$(ssh $SSH_OPTS "$SDW1" \
    "if sudo test -d '$TARGET_DIR'; then echo '$TARGET_DIR'; fi")

if [ -z "$PID_" ] && [ -z "$DIR_" ]; then
    echo "Приступайте к заданию"
else
    echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
    echo "PID: ${PID_:-не найден}"
    echo "DIR: ${DIR_:-не найден}"
    exit 1
fi
