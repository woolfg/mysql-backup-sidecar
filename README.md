# mysql-backup-sidecar

This backup docker container creates incremental and compressed MySQL or MariaDB backups without blocking the database during the backup procedure. It is based on `XtraBackup` https://www.percona.com/doc/percona-xtrabackup/2.4/index.html and the forked version for MariaDB `Mariabackup` https://mariadb.com/kb/en/mariabackup/.

## Features

- non blocking backup procedure (XtraBackup = Mariabackup)
- runs in a separated container
- configurable cron schedule (e.g. every night, every second night, etc)
- configurable backup cycles (incremental, full backups)
- backup rotation (e.g. delete incremental backups after a full backup)
- supports docker credentials and environment based password definitions

## Configuration

The following environment variables are supported (incl. example values):

- `CRON_SCHEDULE:` "5 3 * * *"
- `INCREMENTAL:` "true"
- `COMPRESS_THREADS:` 1
- `BACKUP_DIR:` /backup
- `DIR_DATE_PATTERN:` "%Y%m%d"
- `FULL_BACKUP_DATE_FORMAT:` "%a"
- `FULL_BACKUP_DATE_RESULT:` "Sun"
- `DATABASES_EXCLUDE:` "example example1.table1"
- `ROTATION1_DAYS:` 6
- `ROTATION1_DATE_FORMAT:` "%a"
- `ROTATION1_DATE_RESULT:` "Sun"
- `ROTATION2_DAYS:` 30
- `ROTATION2_DATE_FORMAT:` "%d"
- `ROTATION2_DATE_RESULT:` "<8"
- `ROTATION3_DAYS:` 365
- `ROTATION3_DATE_FORMAT:` "%m"
- `ROTATION3_DATE_RESULT:` "01"
- `MYSQL_USER:` root
- `MYSQL_PASSWORD_FILE:` /run/secrets/db_password
- `MYSQL_HOST:` db

## More Information

Find a blog article about the project at https://wolfgang.gassler.org/docker-image-mysql-mariadb-backups/

## Upload Backup Data

If you want to upload your backups to an external storage we recommend the very flexible docker container https://github.com/lagun4ik/docker-backup

## Credits

Thanks to the following resources which helped and inspired:

- https://www.percona.com/doc/percona-xtrabackup/2.4/index.html
- https://github.com/khoanguyen96/dockerfiles/blob/master/percona-xtrabackup/Dockerfile
- https://www.digitalocean.com/community/tutorials/how-to-configure-mysql-backups-with-percona-xtrabackup-on-ubuntu-16-04
