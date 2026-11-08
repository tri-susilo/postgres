# ============================================================
# PostgreSQL 18.6 + pgBackRest
# Base: official postgres image (pin minor 18.6)
# pgBackRest: dipasang dari repo PGDG (apt.postgresql.org)
# ============================================================

FROM postgres:18.6-bookworm

# Metadata
LABEL org.opencontainers.image.title="postgres-pgbackrest" \
      org.opencontainers.image.description="PostgreSQL 18.6 + pgBackRest" \
      org.opencontainers.image.source="https://github.com/pgbackrest/pgbackrest"

# Pasang pgbackrest + tools pendukung (ssh bila repo remote via ssh, cron utk backup otomatis)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg; \
    # Tambahkan repo PGDG
    install -d /etc/apt/keyrings; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        -o /etc/apt/keyrings/postgresql.asc; \
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.asc] https://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        pgbackrest openssh-client cron; \
    pgbackrest version; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint-override.sh /usr/local/bin/
COPY pgbackrest.conf /etc/pgbackrest/pgbackrest.conf
RUN chmod 755 /usr/local/bin/docker-entrypoint-override.sh

# Samakan perilaku entrypoint official, tapi set dulu konfigurasi pgBackRest
ENTRYPOINT ["docker-entrypoint-override.sh"]
CMD ["postgres"]
