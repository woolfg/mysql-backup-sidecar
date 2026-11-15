# mysql-backup-sidecar

This backup docker container creates incremental and compressed MySQL or MariaDB backups using [Percona XtraBackup](https://docs.percona.com/percona-xtrabackup/) or [MariaDB Backup](https://mariadb.com/docs/server/server-usage/backup-and-restore/mariadb-backup). Read the underlying tool's documentation to understand its locking behavior and restore procedure.

## Features

- non-blocking backup procedure (using XtraBackup/Mariabackup).
- runs in a separated container
- configurable cron schedule (e.g. every night, every second night, etc)
- configurable backup cycles (incremental, full backups)
- backup rotation (e.g. delete incremental backups after a full backup)
- delete old backups automatically after some time to free up disk space
- supports docker credentials and environment based password definitions

## How to get started

To have a running backup system it is sufficient to define the following environment variables:

- `MYSQL_HOST`
- `MYSQL_USER`
- `MYSQL_PASSWORD`

Use the example `docker-compose` file in the `examples` folder to get started.

## Supported database versions

The maintained image variants target these LTS series on `linux/amd64`:

| Database | Sidecar tag | Backup executable |
|----------|-------------|-------------------|
| MySQL 8.4 | `latest-mysql-8.4` | `xtrabackup` 8.4 |
| MySQL 9.7 | `latest-mysql-9.7` | `xtrabackup` 9.7 |
| MariaDB 10.11 | `latest-mariadb-10.11` | `mariadb-backup` 10.11 |
| MariaDB 11.4 | `latest-mariadb-11.4` | `mariadb-backup` 11.4 |
| MariaDB 11.8 | `latest-mariadb-11.8` | `mariadb-backup` 11.8 |
| MariaDB 12.3 | `latest-mariadb-12.3` | `mariadb-backup` 12.3 |

These tags are published after the corresponding image passes full and incremental restore checks, with compression enabled and disabled. Builds run on changes and weekly to pick up upstream patches. Release tags retain the same suffix, for example `0.4.0-mariadb-11.8` when that sidecar release is published.

Choose the sidecar variant matching your server's series. For MariaDB, also match the backup tool's patch version to the server where possible; inspect `mariadb-backup --version`. Prepare backups using the same backup tool version that created them. A successful backup command with a different server series does not establish restore compatibility.

The MySQL 8.0 and MariaDB 10.4/10.5/10.8/10.9 Dockerfiles remain for legacy users, but these EOL series are no longer in the routine build matrix. Previously published tags remain available. Existing ARM64 Dockerfiles are legacy artifacts; ARM64 is not part of the tested publication matrix.

## Config

### Configuration variables

The following environment variables are supported (incl. example values) for configuring the backup system:

| **Key**                | **Example Value**           | **Description**                                                                      |
|------------------------|-----------------------------|--------------------------------------------------------------------------------------|
| `CRON_SCHEDULE`        | "5 3 * * *"                 | Cron schedule for running the backup job (using the standard cron format).           |
| `INCREMENTAL`          | "true"                      | Specifies whether incremental backup should be performed (`true` or `false`).        |
| `COMPRESS_THREADS`     | 1                           | Compression threads; `0` disables compression (default). MySQL uses ZSTD; MariaDB uses its deprecated QuickLZ format. |
| `BACKUP_DIR`           | "/backup"                   | Directory where backup files will be stored.                                         |
| `DIR_DATE_PATTERN`     | "%Y%m%d"                    | Date pattern (command `date` is used) to be used for naming backup directories.      |
| `FULL_BACKUP_DATE_FORMAT` | "%a"                     | Date format (command `date` is used) to be used for naming full backup files.        |  
| `FULL_BACKUP_DATE_RESULT` | "Sun"                    | If the `date` output of the pattern `FULL_BACKUP_DATE_FORMAT` is equals to `FULL_BACKUP_DATE_RESULT` a full backup will be created. |
| `BEFORE_BACKUP_SCRIPT` | "/backup/before_script.sh"  | Path to the script that will be executed before starting the backup.                  |
| `AFTER_BACKUP_SCRIPT`  | "/backup/after_script.sh"   | Path to the script that will be executed after completing the backup.                 |
| `DATABASES_EXCLUDE`    | "db1 db2.table1"            | Databases or tables to be excluded from the backup, separated by space.               |
| `MYSQL_USER`           | "root"                      | MySQL database user for authentication.                                                |
| `MYSQL_PASSWORD`       | "secret"                    | MySQL database password for authentication.                                            |
| `MYSQL_PASSWORD_FILE`  | "/run/secrets/db_password"  | Path to the file containing the MySQL database password (when using e.g. docker secrets). |
| `MYSQL_HOST`           | "db"                        | Hostname or IP address of the MySQL database server.                                   |

### Backup Rotation Configuration

To save disk space, backups should be rotated automatically. The default pattern is:

- every day an incremental backup (`INCREMENTAL=true`)
- every Sunday a full backup (`FULL_BACKUP_DATE_FORMAT="%a"`, `FULL_BACKUP_DATE_RESULT="Sun"`)
- keep weekly backups for a month
- keep monthly backups for a year
- keep yearly backups after one year

To change this behavior, you can use the following environment variables to define three rotation cycles.
Every cycle is defined by a time range of days and a condition based on the Linux `date` command.
The default evaluation used `equals` but can be changed to `greater than` or `less than` by using the operators `<` or `>` as shown in the examples below.

| **Key**                | **Example Value**           | **Description**                                                                      |
|------------------------|-----------------------------|--------------------------------------------------------------------------------------|
| `ROTATION1_DAYS`       | 6                           | condition for backups older than specified number of days                            |
| `ROTATION1_DATE_FORMAT`| "%a"                        | linux `date` pattern that is used in the condition                                   |
| `ROTATION1_DATE_RESULT`| "Sun"                       | expected result of the `date` command to keep the backup                             |
| `ROTATION2_DAYS`       | 30                          | condition for backups older than specified number of days                            |
| `ROTATION2_DATE_FORMAT`| "%d"                        | linux `date` pattern that is used to evaluate the condition                          |
| `ROTATION2_DATE_RESULT`| "<8"                        | expected result of the `date` command to keep the backup                             |
| `ROTATION3_DAYS`       | 365                         | condition for backups older than specified number of days                            |
| `ROTATION3_DATE_FORMAT`| "%m"                        | linux `date` pattern that is used to evaluate the condition                          |
| `ROTATION3_DATE_RESULT`| "01"                        | expected result of the `date` command to keep the backup                             |
| `DELETE_OLDER_DAYS`    | 0                           | delete all backups older than specified number of days (0 = disabled)                |

The examples given above result in the following behavior:

- For backups older than 6 days, only backups that were done on a Sunday are kept.
- For backups older than 30 days, keep the backup that was done on a day of the first week of the month.
- For backups older than 365 days, keep the backup that was done in January.
- In this example yearly backups are kept forever.

## Example configuration

You can find an example configuration in the `examples` folder. The available docker image versions can be found on [Docker Hub](https://hub.docker.com/r/woolfg/mysql-backup-sidecar/tags).

## More Information

Find a blog article about the project at https://wolfgang.gassler.org/docker-image-mysql-mariadb-backups/

## Restore a backup

Work on a copy of your backup: preparation modifies its files. Use the matching sidecar and replace the example paths below. Stop the destination database and disable automatic restarts before copying data back. The destination data directory must be empty.

For compressed backups, first decompress both the full backup and any incremental backup you need. Use `xtrabackup --decompress --remove-original --target-dir=/restore/full` for MySQL or `mariadb-backup --decompress --remove-original --target-dir=/restore/full` for MariaDB. Repeat for the incremental directory. The maintained images include the required decompression utilities (`zstd`/`lz4` for MySQL, `qpress` for MariaDB).

For a full MySQL backup, run `xtrabackup --prepare --target-dir=/restore/full`. For a MySQL incremental restore:

```sh
xtrabackup --prepare --apply-log-only --target-dir=/restore/full
xtrabackup --prepare --target-dir=/restore/full --incremental-dir=/restore/incremental
```

For a MariaDB full or incremental restore:

```sh
mariadb-backup --prepare --target-dir=/restore/full
# Run this only when restoring incremental changes:
mariadb-backup --prepare --target-dir=/restore/full --incremental-dir=/restore/incremental
```

This sidecar bases incremental backups on the newest full backup, so apply the chosen incremental backup to its matching full backup. Confirm that its `from_lsn` matches the full backup's `to_lsn` in the checkpoint file (`mariadb_backup_checkpoints` on newer MariaDB versions, otherwise `xtrabackup_checkpoints`). Backups from other tools may instead require an incremental chain; follow the [XtraBackup](https://docs.percona.com/percona-xtrabackup/8.4/prepare-incremental-backup.html) or [MariaDB Backup](https://mariadb.com/kb/en/incremental-backup-and-restore-with-mariabackup/) instructions for those.

Copy the prepared backup using `xtrabackup --copy-back --target-dir=/restore/full --datadir=/var/lib/mysql` or the equivalent `mariadb-backup --copy-back` command. Set the restored files' ownership to the database container's `mysql` user, then start the database and verify its data.

## Development and verification

`make build` builds the maintained variants. `make runmysql` and `make runmariadb` run the development examples with MySQL 8.4 and MariaDB 11.8 respectively.

```sh
make test-unit
make test-restore DB_FAMILY=mysql DB_VERSION=8.4
make test-restore DB_FAMILY=mariadb DB_VERSION=11.8
```

The restore test builds the selected sidecar, creates isolated Docker containers and named volumes, inserts data, takes full and incremental backups, prepares and restores each into a fresh database, and checks the restored rows. It repeats with compression enabled and cleans up only its own resources. MariaDB tests also check an Aria table. CI runs this for all maintained variants before publishing each image.

A failed backup returns a nonzero exit status, reports `failed` to the after hook and prevents the scheduled rotation. Failed backup checkpoints are renamed with a `.failed` suffix so they cannot be selected as an incremental base. Failed directories remain for diagnosis; move them aside before retrying with the same directory name. A failing before or after hook also prevents rotation.

## Upload Backup Data

- If you want to upload your backups to an external storage we recommend the very flexible docker container https://github.com/lagun4ik/docker-backup
- For uploading backups to Google Cloud Storage automatically, you can use my sister project [woolfg/mysql-backup-sidecar-gs](https://github.com/woolfg/mysql-backup-sidecar-gs).

## After and Before scripts

You can run scripts right before and after backup routines. Just pass `BEFORE_BACKUP_SCRIPT` and/or `AFTER_BACKUP_SCRIPT` environment variables with the files locations.

The before script receives as only one argument the backup's target directory while the after script receives three: the status `succeed` or `failed`, the raw output and the backup's target directory.

## Credits

Contributors:
- [Guillaume L. (guillaumelamirand)](https://github.com/guillaumelamirand)
- [anton z (luzrain)](https://github.com/luzrain)

Thanks to the following resources which helped and inspired:

- https://www.percona.com/doc/percona-xtrabackup/2.4/index.html
- https://github.com/khoanguyen96/dockerfiles/blob/master/percona-xtrabackup/Dockerfile
- https://www.digitalocean.com/community/tutorials/how-to-configure-mysql-backups-with-percona-xtrabackup-on-ubuntu-16-04
