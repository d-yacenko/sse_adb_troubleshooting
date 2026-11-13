#!/bin/bash
set -euo pipefail

DB="adb"
DB_USER="gpadmin"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

# Скрипт запускается на mdw, а действующий master после кейса 4 - msdw.
MDW=$(hostname -f)
MSDW=${MDW/-mdw/-msdw}
[[ "$MSDW" != "$MDW" ]] || { echo "Запустите run.sh с исходного mdw"; exit 1; }
SDW2=${MDW/-mdw/-sdw2}

echo "Подготовка проблемной ситуации..."

# На sdw2 должно быть два wal receiver.
PIDS=$(ssh $SSH_OPTS "$SDW2" \
    "ps -eo pid=,args= | awk '/[w]al receiver process/ {print \$1}' | xargs")

if [ "$(wc -w <<< "$PIDS")" -ne 2 ]; then
    echo "Не удалось определить два процесса wal receiver"
    exit 1
fi

# При повторном запуске сначала размораживаем процессы.
ssh $SSH_OPTS "$SDW2" "sudo kill -CONT $PIDS"
sleep 2

# Нельзя воспроизводить кейс, если mirror уже перешли в down.
BAD_MIRRORS=$(ssh -T $SSH_OPTS "$MSDW" \
    "sudo -iu $DB_USER psql -X -Atq -d $DB -c \
    \"SELECT count(*) FROM gp_segment_configuration
      WHERE content >= 0 AND role = 'm'
        AND (status <> 'u' OR mode <> 's');\"")
if ! [[ "$BAD_MIRRORS" =~ ^[0-9]+$ ]] || [ "$BAD_MIRRORS" -ne 0 ]; then
    echo "Mirror-сегменты не синхронизированы. Сначала восстановите их (gprecoverseg)."
    exit 1
fi

# Эксперимент: увеличиваем таймауты репликации до 12 часов.
# Параметры сохраняются при перезагрузке ОС!
# Исходные значения сохраняем на msdw для последующего ручного возврата.
ssh -T $SSH_OPTS "$MSDW" 'sudo -iu gpadmin bash -s' <<'CONFIG'
set -euo pipefail

TIMEOUT_MS=43200000
TIMEOUT_S=43200
SAVE="$HOME/exercise8_timeouts_before.txt"

# Проверяем наличие основных GUC до изменения конфигурации.
for NAME in wal_sender_timeout wal_receiver_timeout gp_segment_connect_timeout; do
    FOUND=$(psql -X -Atq -d postgres \
        -c "SELECT count(*) FROM pg_settings WHERE name = '$NAME';")
    if [ "$FOUND" != "1" ]; then
        echo "Параметр $NAME не найден в этой сборке ADB"
        exit 1
    fi
done

if [ ! -e "$SAVE" ]; then
    {
        echo "# Настройки до первого запуска exercise 8"
        date
        for NAME in wal_sender_timeout wal_receiver_timeout \
                    gp_segment_connect_timeout gp_fts_mark_mirror_down_grace_period; do
            gpconfig -s "$NAME" || true
            echo
        done
    } > "$SAVE"
fi

echo "Исходные настройки сохранены в $SAVE"
gpconfig -c wal_sender_timeout -v "${TIMEOUT_MS}ms"
gpconfig -c wal_receiver_timeout -v "${TIMEOUT_MS}ms"
gpconfig -c gp_segment_connect_timeout -v "$TIMEOUT_S"

# В GP6 максимальный grace period обычно равен 3600 секундам.
# Если GUC отсутствует в конкретной сборке, просто пропускаем его.
GRACE_MAX=$(psql -X -Atq -d postgres \
    -c "SELECT max_val FROM pg_settings
        WHERE name = 'gp_fts_mark_mirror_down_grace_period';")
if [[ "$GRACE_MAX" =~ ^[0-9]+$ ]]; then
    GRACE=3600
    if [ "$GRACE_MAX" -lt "$GRACE" ]; then
        GRACE=$GRACE_MAX
    fi
    gpconfig -c gp_fts_mark_mirror_down_grace_period -v "$GRACE"
else
    echo "gp_fts_mark_mirror_down_grace_period отсутствует, пропускаем"
fi

# Применяем параметры без полного перезапуска кластера.
gpstop -u

echo "Экспериментальные значения:"
for NAME in wal_sender_timeout wal_receiver_timeout \
            gp_segment_connect_timeout gp_fts_mark_mirror_down_grace_period; do
    gpconfig -s "$NAME" || true
done
CONFIG

# Подготавливаем таблицу на исправном кластере.
ssh -T $SSH_OPTS "$MSDW" "sudo -iu $DB_USER psql -X -v ON_ERROR_STOP=1 -d $DB" <<'SQL' >/dev/null
DROP TABLE IF EXISTS public.write_test;
CREATE TABLE public.write_test (id bigint, payload text)
WITH (appendonly=false) DISTRIBUTED RANDOMLY;
SQL

# Создаем неисправность: останавливаем оба wal receiver на sdw2.
ssh $SSH_OPTS "$SDW2" "sudo kill -STOP $PIDS"
sleep 1

for PID in $PIDS; do
    STATE=$(ssh $SSH_OPTS "$SDW2" "ps -o stat= -p '$PID'" | tr -d '[:space:]')
    [[ "$STATE" == *T* ]] || {
        echo "Не удалось остановить процессы wal receiver"
        exit 1
    }
done

echo "Подготовка завершена"
echo "Приступайте к заданию"
