#!/bin/bash
# Wrapper di atas entrypoint official postgres:image
# - menyiapkan direktori pgBackRest
# - (opsional) menjadwalkan backup otomatis via cron (PG_BACKUP_CRON=1)

set -e

mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest
chmod 750 /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest

# Validasi file konfigurasi
if [ -f /etc/pgbackrest/pgbackrest.conf ]; then
    echo "pgbackrest config: $(pgbackrest version) - $(grep -c . /etc/pgbackrest/pgbackrest.conf) baris konfigurasi"
else
    echo "WARNING: /etc/pgbackrest/pgbackrest.conf tidak ditemukan"
fi

# Cron backup otomatis (contoh: full-backup harian jam 02:00)
if [ "${PG_BACKUP_CRON:-0}" = "1" ]; then
    CRON_SCHEDULE="${PG_BACKUP_CRON_SCHEDULE:-0 2 * * *}"
    STANZA="${PGBACKREST_STANZA:-main}"
    mkdir -p /var/spool/cron/crontabs /var/log/pgbackrest
    cat > /var/spool/cron/crontabs/postgres <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${CRON_SCHEDULE} pgbackrest --stanza=${STANZA} backup >> /var/log/pgbackrest/backup-cron.log 2>&1
EOF
    chown postgres:postgres /var/spool/cron/crontabs/postgres
    chmod 600 /var/spool/cron/crontabs/postgres
    cron
    echo "cron backup aktif: '${CRON_SCHEDULE}' (log: /var/log/pgbackrest/backup-cron.log)"
fi

# Lanjut ke entrypoint official postgres (terletak di /usr/local/bin/docker-entrypoint.sh)
exec docker-entrypoint.sh "$@"
