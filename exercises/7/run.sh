#!/bin/bash
set -euo pipefail

# После кейса 4 запускаем упражнение на новом active master.
[[ "$(hostname -s)" == *-msdw1 ]] || { echo "Запустите упражнение на msdw1"; exit 1; }

echo "Поломка запущена..."

sudo -iu gpadmin bash <<'EOF'
set -e
gpconfig -c 'gp_default_storage_options' -v 'appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5' > /dev/null 2>&1
psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER DATABASE postgres SET search_path = task, pg_catalog" > /dev/null 2>&1
psql -v ON_ERROR_STOP=1 -d adb -c "ALTER DATABASE adb SET search_path = task, pg_catalog" > /dev/null 2>&1
gpconfig -c default_transaction_read_only -v on > /dev/null 2>&1
gpstop -u > /dev/null 2>&1
EOF

echo "Приступайте к заданию"
