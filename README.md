# PostgreSQL 18.6 + pgBackRest → Biznet Gio NEO Object Storage

Image Docker berisi PostgreSQL **18.6** dan **pgBackRest 2.60.0**, archiving WAL dan
full/integritas backup diarahkan ke **NEO Object Storage** Biznet Gio (S3-compatible,
path-style, HTTPS).

## isi file

| File | Keterangan |
|---|---|
| `Dockerfile` | Base `postgres:18.6-bookworm` + pgBackRest dari repo PGDG |
| `docker-compose.yml` | Database + cron backup + helper `info` |
| `pgbackrest.conf` | Konfigurasi stanza & repo S3 (kredensial di-override via env) |
| `docker-compose.restore.yml` | Compose khusus proses restore / disaster recovery |
| `docker-entrypoint-override.sh` | Set direktori pgBackRest + pasang cron backup otomatis |
| `.env.example` | Contoh isi kredensial NEO Object Storage |

## 1. Siapkan Object Storage di console NEO

1. Buka **https://console.neo.id** → **Object Storage** → buat bucket (contoh: `pgbackup`).
2. Di menu **Access Key**, buat Access Key & Secret Key.
3. Catat juga **region** bucket (tertera di console, misal `id-jakarta`).

## 2. Konfigurasi

```bash
cp .env.example .env
# isi S3_BUCKET, S3_ACCESS_KEY, S3_ACCESS_KEY_SECRET, S3_REGION
```

Env yang dipakai (di-.env):

```
S3_ENDPOINT=s3.neo.id
S3_URI_STYLE=path
S3_TLS_VERIFY=y
```

Env `S3_*` dipetakan ke override pgBackRest `PGBACKREST_REPO1_S3_*`
(lihat blok `x-s3-env` di `docker-compose.yml`), kredensial **tidak** ditulis
di file `pgbackrest.conf`.

> `S3_TLS_VERIFY=y` menolak sertifikat self-signed — dianjurkan untuk HTTPS production.

## 3. Jalankan & buat stanza

```bash
docker compose build
docker compose up -d           # postgres jalan, WAL archive aktif
```

Buat stanza di dalam container db:

```bash
docker compose exec -u postgres db pgbackrest --stanza=main stanza-create
```

## 4. Backup

###Manual
```bash
# full backup
docker compose exec -u postgres db pgbackrest --stanza=main --type=full backup

# differential backup
docker compose exec -u postgres db pgbackrest --stanza=main --type=diff backup

# cek isi repo
docker compose --profile backup run --rm pgbackrest
```

### Otomatis (aktif default)
Cron di dalam container db berjalan setiap jam **02:00**
(env `PG_BACKUP_CRON=1`, jadwal: `PG_BACKUP_CRON_SCHEDULE`).
Log backup cron → `/var/log/pgbackrest/backup-cron.log`.

## 5. Retensi

`repo1-retention-full=2` (2 full backup)
`repo1-retention-diff=4` (4 diff backup terakai)

aging (expire) berjalan otomatis di akhir tiap backup.

## 6. Restore

```bash
# 1) hentikan postgres agar datadir tidak dipakai
docker compose stop db

# 2) restore full/delta (default: backup terbaru)
docker compose --profile restore run --rm pgbackrest-restore

# 3) start lagi
docker compose start db
```

### Restore ke point-in-time

Override service restore sesuai kebutuhan:

```bash
# ke backup set tertentu
docker compose --profile restore run --rm \
    pgbackrest-restore --stanza=main --delta --set=20261108-150924F restore

# ke titik waktu tertentu
docker compose --profile restore run --rm \
    pgbackrest-restore --stanza=main --delta \
    --type=time --target="2026-11-08 14:00:00" --target-action=promote restore
```

> Cek label backup yang tersedia terlebih dahulu:
> `docker compose --profile backup run --rm pgbackrest`

## 6b. Restore penuh di host baru / disaster recovery

Untuk skenario total-restore (khususnya di host yang baru/segel), gunakan
`docker-compose.restore.yml` — berdiri sendiri, tidak butuh stack production:

```bash
# (pastikan .env sudah berisi kredensial S3 NEO)
cp .env.example .env   # lalu isi S3_* sesuai console NEO

# 1) reset volume kerja DR (data lama hilang!)
docker compose -f docker-compose.restore.yml down -v

# 2) restore backup terbaru dari S3 ke volume baru
docker compose -f docker-compose.restore.yml run --rm restore

#    restores spesifik:
#    RESTORE_SET=20261108-150924F docker compose -f docker-compose.restore.yml run --rm restore
#    RESTORE_TARGET="2026-11-08 14:00:00" docker compose -f docker-compose.restore.yml run --rm restore

# 3) start postgres dari data hasil restore (otomatis tunggu restore selesai)
docker compose -f docker-compose.restore.yml up -d

# cek daftar backup yang ada di S3 tanpa restore
docker compose -f docker-compose.restore.yml --profile info run --rm info
```

Penting:
- Volume di file ini (`restore-data`, dst.) **terpisah** dari production
  (`db-data`), jadi uji- restore tidak menimpa data production.
- Setelah restore selesai, pgBackRest otomatis melanjutkan WAL-archive ke repo
  yang sama (archive-push berjalan kembali; timeline setelah recovery ikut
  termasuk `.history`).
- Bila ingin restore langsung menimpa data production di host yang sama, stop
  stack production dulu (`docker compose down`), lalu gunakan helper
  `pgbackrest-restore` pada `docker-compose.yml` (bagian 6) yang sudah
  share volume `db-data`.

## 7. Check / verify

```bash
docker compose exec -u postgres db pgbackrest --stanza=main check   # end-to-end WAL archiving
docker compose exec -u postgres db pgbackrest verify                # verify isi file backup sekaligus checksum
docker compose exec -u postgres db pgbackrest --stanza=main info    # informasi backup
```

## Catatan

- **Endpoint NEO** menggunakan path-style (`https://s3.neo.id/<bucket>/<path>`)
  dan TLS (443). Seluruh kredensial dipasok via env `PGBACKREST_REPO1_S3_*`.
- pgBackRest upload menggunakan kompresi `zst` (level 3) dengan `process-max=4`.
- `repo1-path=/pgbackrest` di `pgbackrest.conf` adalah lokasi folder di dalam bucket;
  silakan ubah sesuai kebijakan penamaan Anda.
- Pantau health backup secara rutin dengan `pgbackrest --stanza=main check`.
