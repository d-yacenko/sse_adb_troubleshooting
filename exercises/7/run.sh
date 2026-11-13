#!/bin/bash
set -euo pipefail

MDW=$(hostname -f)
MSDW=${MDW/-mdw/-msdw1}
[[ "$MSDW" != "$MDW" ]] || { echo "Запустите run.sh с исходного mdw"; exit 1; }
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5"

echo "Поломка запущена..."

ssh -T $SSH_OPTS "$MSDW" 'sudo -iu gpadmin bash -s' <<'EOF'
set -e
gpconfig -c 'gp_default_storage_options' -v 'appendoptimized=true, orientation=column, compresstype=zstd, compresslevel=5' > /dev/null 2>&1
psql -v ON_ERROR_STOP=1 -d postgres -c "ALTER DATABASE postgres SET search_path = task, pg_catalog" > /dev/null 2>&1
psql -v ON_ERROR_STOP=1 -d adb -c "ALTER DATABASE adb SET search_path = task, pg_catalog" > /dev/null 2>&1
gpconfig -c default_transaction_read_only -v on > /dev/null 2>&1
gpstop -u > /dev/null 2>&1
EOF

echo "Приступайте к заданию"
