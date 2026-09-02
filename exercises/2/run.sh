#!/bin/bash
set -euo pipefail

MDW=$(hostname)
SDW1=$(echo "$MDW" | sed 's/mdw/sdw1/g')

PID=$(ssh -o StrictHostKeyChecking=accept-new "$SDW1" \
    "ps aux | awk '/[p]ostgres/ && /gpseg0/ {print \$2}'")

if [ -z "$PID" ]; then
    echo "Уже все готово, приступайте к заданию"
    exit 0
fi

ssh -o StrictHostKeyChecking=accept-new "$SDW1" \
    "sudo kill -9 $PID"

PID_=$(ssh -o StrictHostKeyChecking=accept-new "$SDW1" \
    "ps aux | awk '/[p]ostgres/ && /gpseg0/ {print \$2}'")

if [ -z "$PID_" ]; then
    echo "Приступайте к заданию"
else
    echo "Что-то пошло не так, скрипт не сработал, свяжитесь с организаторами"
fi
