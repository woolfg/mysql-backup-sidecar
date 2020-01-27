# mysql-backup-sidecar

This backup docker container creates incremental and compressed MySQL or MariaDB (InnoDB) backups without blocking the database during the backup procedure. It is based on XtraBackup https://www.percona.com/doc/percona-xtrabackup/2.4/index.html

## Features

- non blocking backup procedure of InnoDB based databases (XtraBackup)
- runs in a separated container
- configurable cron schedule (e.g. every night, every second night, etc)
- configurable backup cycles (incremental, full backups)
- backup rotation (e.g. delete incremental backups after a full backup)
- supports docker credentials and environment based password definitions

## Configuration

The following environment variables are supported (incl. example values):

- `CRON_SCHEDULE: "05 05 * * *"`
- `INCREMENTAL: "true"`
- `COMPRESS_THREADS: 1`
- `TARGET_DIR: /backup`
- `FULL_DATE_PATTERN: "%Y_week%W"`
- `INCREMENTAL_DATE_PATTERN: "%Y%m%d_baseweek_%W"`
- `MYSQL_USER: root`
- `MYSQL_PASSWORD_FILE: /run/secrets/db_password`
- `DEBUG: "true"`

## Upload Backup Data

If you want to upload your backups to an external storage we recommend the very flexible docker container https://github.com/lagun4ik/docker-backup

## Credits

Thanks to the following resources which helped and inspired:

- https://www.percona.com/doc/percona-xtrabackup/2.4/index.html
- https://github.com/khoanguyen96/dockerfiles/blob/master/percona-xtrabackup/Dockerfile
- https://www.digitalocean.com/community/tutorials/how-to-configure-mysql-backups-with-percona-xtrabackup-on-ubuntu-16-04